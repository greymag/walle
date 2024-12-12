import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

/// Command to export keys for translation.
class ExportL10nCommand extends BaseL10nCommand {
  static const _argPath = 'path';
  static const _argLocale = 'locale';

  ExportL10nCommand()
      : super(
          'export',
          'Export missed keys for translation with base values.',
        ) {
    argParser
      ..addOption(
        _argPath,
        abbr: 'p',
        help: 'Project path.',
        valueHelp: 'PATH',
      )
      ..addOption(
        _argLocale,
        abbr: 'l',
        help: 'Locale to check for missed translations.',
        valueHelp: 'LOCALE',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final path = args[_argPath] as String?;
    final locale = args[_argLocale] as String?;
    // TODO: add argument
    final fileName = defaultFileName;

    if (path == null || locale == null) {
      return error(1, message: 'Path and locale are required.');
    }

    try {
      const subPath = 'src/main/res/';
      final dir = Directory(p.join(path, subPath));

      final baseFile = getXmlFileByLocaleIfExist(
            dir,
            baseLocaleForTranslate,
            fileName,
            isAndroidProject: true,
          ) ??
          getXmlFileByLocale(
            dir,
            baseLocale,
            fileName,
            isAndroidProject: true,
          );
      final translationFile = getXmlFileByLocale(
        dir,
        locale,
        fileName,
        isAndroidProject: true,
      );

      if (!translationFile.existsSync()) {
        printVerbose('Not found ${translationFile.path}');
        return error(2,
            message: 'Translation file for locale $locale not found.');
      }

      final baseXml = await loadXml(baseFile);
      final translationXml = await loadXml(translationFile);

      final translationResources = translationXml.resources.children;
      final forTranslation = <XmlElement>{};
      baseXml.forEachResource((child) {
        final name = child.attributeName;
        if (!translationResources
            .any((c) => c is XmlElement && c.attributeName == name)) {
          final newNode = child.copy();
          forTranslation.add(newNode);
        }
      });

      if (forTranslation.isNotEmpty) {
        printInfo('Found ${forTranslation.length} strings for translation.');

        final xml4Translation = XmlDocument([
          XmlElement(XmlName.fromString('resources')),
        ]);
        xml4Translation.resources.children..addAll(forTranslation);

        final content = xml4Translation.toXmlString(
          pretty: true,
          indent: indent,
          entityMapping: defaultXmlEntityMapping(),
        );

        final buffer = StringBuffer();
        buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
        buffer.write(content);

        // TODO: target file path
        final targetFile = File(fileName);
        targetFile.writeAsStringSync(buffer.toString());

        printInfo(
            'Saved to ${targetFile.absolute.path}. Send it to translators.');
      } else {
        printVerbose('Nothing to translate.');
      }

      return success(message: 'All strings transferred.');
    } on RunException catch (e) {
      return exception(e);
    } catch (e, st) {
      printVerbose('Exception: $e\n$st');
      return error(2, message: 'Failed by: $e');
    }
  }
}
