import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:walle/src/api/google_sheets/google_sheets_api.dart';
import 'package:xml/xml.dart';

/// Command to import translations from Google Docs (sheets).
class GoolgedocImportL10nCommand extends BaseL10nCommand {
  static const _argFrom = 'from';
  static const _argPath = 'path';
  // static const _argLocale = 'locale';

  GoolgedocImportL10nCommand()
      : super(
          'googledoc',
          'Import translations from Google Docs (sheet).',
        ) {
    argParser
      ..addOption(
        _argFrom,
        abbr: 'f',
        help: 'Google Sheet url.',
        valueHelp: 'URL',
      )
      ..addOption(
        _argPath,
        abbr: 'p',
        help: 'Project path.',
        valueHelp: 'PATH',
      );
    // ..addOption(
    //   _argLocale,
    //   abbr: 'l',
    //   help: 'Locale to check for missed translations.',
    //   valueHelp: 'LOCALE',
    // );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final fromUrl = args[_argFrom] as String?;
    final path = args[_argPath] as String?;
    // final locale = args[_argLocale] as String?;

    if (fromUrl == null || path == null) {
      // || locale == null) {
      return error(1, message: 'Path and locale are required.');
    }

    try {
      const subPath = 'src/main/res/'; // TODO: вынести
      final dir = Directory(p.join(path, subPath));

      printVerbose('Connecting to Google Docs...');
      final api = await _connectGoogleDocs();
      if (api == null) {
        return error(1, message: 'Failed to connect to Google Docs.');
      }
      printVerbose('Connected.');

      printVerbose('Load $fromUrl');
      final document = await api.loadDocument(fromUrl);
      printVerbose('Document loaded, ${document.sheets?.length} sheets');

      // TODO: sheet as arg of get from url
      final sheet = document.sheets!.first;
      printVerbose('Selected sheet: ${sheet.properties?.title}');

      final data = sheet.data!.first;
      final rows = data.rowData!;

      final headerRowCells = rows.first.values!;
      var idIndex = -1;
      final localeIndexes = <String, int>{};
      for (var i = 0; i < headerRowCells.length; i++) {
        final cell = headerRowCells[i];
        final value = cell.formattedValue;
        if (value == null) continue;

        final normalizedValue = value.toLowerCase().trim();
        if (normalizedValue == 'id') {
          idIndex = i;
        } else if (idIndex != -1) {
          final endIndex = normalizedValue.indexOf('(');
          final locale = endIndex == -1
              ? normalizedValue
              : normalizedValue.substring(0, endIndex).trimRight();
          localeIndexes[locale] = i;
        }
      }

      final dataRows = rows
          .sublist(1)
          .takeWhile((row) => row.values?[idIndex].formattedValue != null);

      final baseFile = getXmlFileByLocaleIfExist(dir, baseLocaleForTranslate) ??
          getXmlFileByLocale(dir, baseLocale);
      final baseXml = await loadXml(baseFile);
      final allowedIds = <String>{};
      baseXml.forEachResource((child) => allowedIds.add(child.attributeName));

      // TODO: move to args?
      const localeForBase = 'zh-rCN';
      const fallbackLocales = {
        'no-rno': 'no',
        'nn-rno': 'no',
        'nb-rno': 'no',
      };
      final indentNode = XmlText(indent);
      final nlNode = XmlText('\n');

      int? getValueIndex(String locale) {
        final key = locale.toLowerCase();
        if (localeIndexes.containsKey(key)) return localeIndexes[key];
        if (fallbackLocales.containsKey(key)) {
          return getValueIndex(fallbackLocales[key]!);
        }
        return null;
      }

      var statLinesAddedCount = 0;
      var statLinesChangedCount = 0;
      var statLocalesCount = 0;
      var statLocalesFailedCount = 0;

      printVerbose('Start iterating over strings files');
      await forEachStringsFile(dir, (dirName, file, l) async {
        final locale = l == baseLocale ? localeForBase : l;
        printVerbose('$locale: ${file.path}');

        final valueIndex = getValueIndex(locale);
        if (valueIndex == null) {
          printError('Not found column in document for locale $locale');
          statLocalesFailedCount++;
        } else {
          final xml = await loadXml(file);
          final xmlResources = xml.resources.children;
          final childrenById = <String, XmlElement>{};
          xml.forEachResource((child) {
            childrenById[child.attributeName] = child;
          });

          var addedCount = 0;
          var changedCount = 0;
          for (final row in dataRows) {
            final cells = row.values!;
            final idCell = cells[idIndex];
            final valueCell = cells[valueIndex];

            final value = valueCell.formattedValue;
            if (value == null || value.isEmpty) continue;

            final id = idCell.formattedValue;
            if (!allowedIds.contains(id)) {
              printVerbose('\tSkip <$id>');
              continue;
            }

            if (childrenById.containsKey(id)) {
              final child = childrenById[id]!;
              if (child.innerText != value) {
                child.innerText = value;
                changedCount++;
              }
            } else {
              final child = XmlElement(XmlName.fromString('string'));
              child.setAttribute('name', id);
              child.innerText = value;
              xmlResources
                ..add(indentNode.copy())
                ..add(child)
                ..add(nlNode.copy());

              addedCount++;
            }
          }

          if (addedCount > 0 || changedCount > 0) {
            printVerbose('\t$addedCount items added, $changedCount changed');

            final content = xml.toXmlString(
              entityMapping: defaultXmlEntityMapping(),
            );
            file.writeAsStringSync(content);

            statLinesAddedCount += addedCount;
            statLinesChangedCount += changedCount;
            statLocalesCount++;
          }
        }
      });
      printVerbose('Done');

      final statLinesCount = statLinesAddedCount + statLinesChangedCount;
      final String message;
      if (statLinesCount > 0) {
        final sb = StringBuffer();
        sb.write('Imported $statLinesCount lines for $statLocalesCount locales '
            '($statLinesAddedCount added, $statLinesChangedCount changed).');

        if (statLocalesFailedCount > 0) {
          sb.write(' $statLocalesFailedCount locales failed.');
        }

        message = sb.toString();
      } else {
        message = 'No lines imported';
      }

      return success(message: message);
    } on RunException catch (e) {
      return exception(e);
    } catch (e, st) {
      printVerbose('Exception: $e\n$st');
      return error(2, message: 'Failed by: $e');
    }
  }

  Future<GoogleSheetsApi?> _connectGoogleDocs() async {
    final client = GoogleSheetsApi(printInfo, log: printVerbose);
    return await client.connect() ? client : null;
  }
}
