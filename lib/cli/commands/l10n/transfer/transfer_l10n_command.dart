import 'dart:io';

import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';

/// Command to transfer translations from one project to another.
class TransferL10nCommand extends BaseL10nCommand {
  static const _argFrom = 'from';
  static const _argTo = 'to';
  static const _argLocales = 'locales';
  static const _argFromFileName = 'filename';
  static const _argToFileName = 'to-filename';
  static const _argKeys = 'keys';
  static const _argFromType = 'from-type';
  static const _argAll = 'all';

  TransferL10nCommand()
      : super(
          'transfer',
          'Transfer localization strings from one project to another.',
        ) {
    argParser
      ..addOption(
        _argFrom,
        abbr: 'f',
        help: 'Source project path.',
        valueHelp: 'PATH',
      )
      ..addOption(
        _argTo,
        abbr: 't',
        help: 'Target project path.',
        valueHelp: 'PATH',
      )
      ..addOption(
        _argLocales,
        abbr: 'l',
        help: 'Locales to transfer.',
        valueHelp: 'en-US,pt-PT,...',
      )
      ..addOption(
        _argKeys,
        abbr: 'k',
        help: 'Keys to transfer. If not defined - all missed keys, '
            'presented at main locale will be transferred. '
            'Use --$_argAll to transfer all keys from source. '
            'You can use format key=alias if you want to rename the key during transfer.',
        valueHelp: 'key1,key2,...',
      )
      ..addOption(
        _argFromFileName,
        abbr: 'n',
        help: 'Name of the file to work with',
        valueHelp: 'my_filename',
        defaultsTo: defaultFileName,
      )
      ..addOption(
        _argToFileName,
        abbr: 'o',
        help: 'Name of the target file fpr transfer. '
            'By default equals to $_argFromFileName',
        valueHelp: 'target_filename',
      )
      ..addOption(
        _argFromType,
        help: 'Name of the file to work with',
        valueHelp: 'my_filename',
        defaultsTo: XmlFileType.string.name,
        allowed: XmlFileType.names,
      )
      ..addFlag(
        _argAll,
        abbr: 'a',
        help: 'If --$_argKeys not defined, than transfer all keys from source, '
            "rather than only presented at the target's at main locale",
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final fromPath = args[_argFrom] as String?;
    final toPath = args[_argTo] as String?;
    final locales = (args[_argLocales] as String?)?.split(',');
    final fromType = XmlFileType.byName(args[_argFromType]! as String);

    final fromFileName =
        getXmlFilename(args[_argFromFileName] as String?, defaultFileName);
    final toFileName =
        getXmlFilename(args[_argToFileName] as String?, fromFileName);

    final argKeys = (args[_argKeys] as String?)?.split(',');
    final transferAll =
        argKeys?.isNotEmpty != true && (args[_argAll] ?? false) as bool;

    const toType = XmlFileType.string;

    // TODO: move to args?
    const androidLocalesMap = {
      // '': 'en',
      // 'zh-rCN': '',
      'en': '',
    };
    const emptyLocalesMap = <String, String>{};
    final android2NonAndroidMap = <String, String>{
      ...getAndroidLocaleAliasesMap(),
      'nb': 'no',
      'b+sr+Latn': 'sr',
      '': 'en',
    };

    final nonAndroid2AndroidMap =
        android2NonAndroidMap.map((k, v) => MapEntry(v, k));

    if (fromPath == null || toPath == null) {
      return error(1, message: 'Both paths are required.');
    }

    try {
      final (fromDir, isFromAndroidProject) = getResDir(fromPath, fromType);
      final (toDir, isToAndroidProject) = getResDir(toPath, toType);

      printVerbose(
          'Transfer from ${fromDir.path} [${isFromAndroidProject ? 'android project' : 'non-android project'}] '
          'to ${toDir.path} [${isToAndroidProject ? 'android project' : 'non-android project'}] ');

      printVerbose('From file: $fromFileName, to file: $toFileName');

      final fromLocalesMap = isFromAndroidProject
          ? androidLocalesMap
          : (isToAndroidProject
              ? nonAndroid2AndroidMap // TODO: check, maybe android2NonAndroidMap?
              : emptyLocalesMap);

      final toLocalesMap = isToAndroidProject
          ? androidLocalesMap
          : (isFromAndroidProject ? nonAndroid2AndroidMap : emptyLocalesMap);

      final keysMap = <String, String>{};
      final arrayIndexByKey = <String, int>{};
      final keys = argKeys?.map((k) {
            final parts = k.split('=');
            var fromKey = parts.first;
            if (fromType == XmlFileType.stringArray && fromKey.contains('[')) {
              final keyParts =
                  fromKey.substring(0, fromKey.length - 1).split('[');
              fromKey = keyParts[0];
              arrayIndexByKey[fromKey] = int.parse(keyParts[1]);
            }

            if (parts.length == 2) keysMap[fromKey] = parts[1];
            return fromKey;
          }) ??
          await _getAllKeys(
            fromDir,
            toDir,
            fromFileName,
            toFileName,
            fromLocalesMap,
            isFromAndroidProject: isFromAndroidProject,
            isToAndroidProject: isToAndroidProject,
            allFromSource: transferAll,
            validateByBase: locales != null,
          );

      printVerbose('Keys for transfer: ${keys.join(', ')}.');

      final importData = <String, File>{};
      await forEachStringsFile(
        fromDir,
        fromFileName,
        (dirName, file, locale) async {
          importData[locale] = file;
        },
        isAndroidProject: isFromAndroidProject,
      );

      printVerbose('Import locales: ${importData.keys.join(', ')}.\n'
          'Total: ${importData.length}');

      File? lookupImportFile(String locale) {
        final file = importData[locale];
        if (file != null) return file;
        printVerbose('Not found file for $locale, try fallback');
        if (locale.contains('-')) {
          return lookupImportFile(locale.substring(0, locale.indexOf('-')));
        } else if (locale.contains('_')) {
          return lookupImportFile(locale.substring(0, locale.indexOf('_')));
        } else {
          // try compatible
          final compatMap = {'no': 'nb'};

          final compatLocale = compatMap[locale];
          if (compatLocale != null) {
            return lookupImportFile(compatLocale);
          }

          // TODO: reversed lookup
        }
        return null;
      }

      final allowedFromTypes = {fromType};

      final expectedLocales = <String>{};
      final processedLocales = <String>{};
      final changedLocales = <String>{};
      var totalStat = XmlTransferStat();

      await forEachStringsFile(
        toDir,
        toFileName,
        (dirName, file, locale) async {
          final toLocale = locale;
          final toFile = file;

          if (locales != null && !locales.contains(toLocale)) return;

          expectedLocales.add(toLocale);
          String fromLocale;

          printVerbose(
              'Checking import source for file ${toFile.path} [$toLocale]');

          // print('toLocalesMap:$toLocalesMap');

          if (toLocalesMap.containsKey(toLocale)) {
            fromLocale = toLocalesMap[toLocale]!;
          } else {
            // TODO: basically we need to check separator, it may be "-" and if this is not android project
            // "-r" very unreliable too. Maybe we can check for existence with fallbacks
            if (isFromAndroidProject == isToAndroidProject) {
              fromLocale = toLocale;
            } else if (isToAndroidProject) {
              fromLocale = toLocale.replaceAll('-r', '_').replaceAll('-', '_');
            } else {
              fromLocale = toLocale.replaceAll('_', '-r');
            }
          }

          printVerbose('Checking locale for import: $fromLocale');
          final fromFile = lookupImportFile(fromLocale);
          if (fromFile == null) {
            printVerbose('Not found, skipping');
            return;
          }

          printVerbose('Found ${fromFile.path}');
          printVerbose('Processing $toLocale...');

          processedLocales.add(toLocale);

          final fromXml = await loadXml(fromFile);
          final toXml = await loadXml(toFile);

          final (:added, :changed, :stat) = transferStrings(
            fromXml,
            toXml,
            supportedTypes: allowedFromTypes,
            neededKeys: keys,
            toType: toType,
            arrayIndexByKey: arrayIndexByKey,
            keysMap: keysMap,
          );

          totalStat += stat;

          if (added.isNotEmpty || changed.isNotEmpty) {
            changedLocales.add(toLocale);
            printInfo('${toFile.path}: ${[
              if (added.isNotEmpty) 'added: ${added.length}',
              if (changed.isNotEmpty) 'changed: ${changed.length}',
            ].join(', ')}');
            await writeXml(toFile, toXml);
          } else {
            printVerbose('Nothing');
          }
        },
        isAndroidProject: isToAndroidProject,
      );

      printSummary(
        changedLocales,
        processedLocales,
        expectedLocales,
        totalStat,
      );

      return success(message: 'Done.');
    } on RunException catch (e) {
      return exception(e);
    } catch (e, st) {
      printVerbose('Exception: $e\n$st');
      return error(2, message: 'Failed by: $e');
    }
  }

  Future<List<String>> _getAllKeys(
    Directory fromDir,
    Directory toDir,
    String fromFileName,
    String toFileName,
    Map<String, String> localesMap, {
    required bool isFromAndroidProject,
    required bool isToAndroidProject,
    bool allFromSource = false,
    bool validateByBase = false,
  }) async {
    final fromLocale = baseLocale;
    final toLocale =
        validateByBase ? (localesMap[fromLocale] ?? baseLocale) : baseLocale;
    final fromMap = await loadValuesByKeys(getXmlFileByLocale(
      fromDir,
      fromLocale,
      fromFileName,
      isAndroidProject: isFromAndroidProject,
    ));
    final toMap = await loadValuesByKeys(getXmlFileByLocale(
      toDir,
      toLocale,
      toFileName,
      isAndroidProject: isToAndroidProject,
    ));
    return toMap.keys.where((key) {
      if (allFromSource) return true;
      if (!fromMap.containsKey(key)) return false;

      if (validateByBase &&
          toMap.val4Compare(key) != fromMap.val4Compare(key)) {
        printVerbose('Skip $key because values are not equal');
        printVerbose('  from: ${fromMap[key]}');
        printVerbose('    to: ${toMap[key]}');
        return false;
      }

      return true;
    }).toList();
  }
}

extension _MapExtension on Map<String, String> {
  String trimmedValue(String key) {
    var text = this[key]!;
    const trimmed = {'.'};

    while (text.isNotEmpty) {
      text = text.trim();
      final len = text.length;
      if (len > 0 && trimmed.contains(text[len - 1])) {
        text = text.substring(0, len - 1);
      } else {
        break;
      }
    }

    return text;
  }

  String val4Compare(String key) => trimmedValue(key).toLowerCase();
}
