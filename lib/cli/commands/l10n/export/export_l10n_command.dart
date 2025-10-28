import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

/// Command to export keys for translation.
class ExportL10nCommand extends BaseL10nCommand {
  static const _argPath = 'path';
  static const _argLocale = 'locale';
  static const _argName = 'name';
  static const _argOutput = 'output';

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
        mandatory: true,
      )
      ..addOption(
        _argLocale,
        abbr: 'l',
        help: 'Locale to check for missed translations.',
        valueHelp: 'LOCALE',
        mandatory: true,
      )
      ..addOption(
        _argName,
        abbr: 'n',
        help: 'Filename for export (without an extension).',
        valueHelp: 'FILENAME',
      )
      ..addOption(
        _argOutput,
        abbr: 'o',
        help: 'Output filename (without an extension).',
        valueHelp: 'FILENAME',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final path = args[_argPath] as String?;
    final locale = args[_argLocale] as String?;
    final sourceName = args[_argName] as String?;
    final outputName = args[_argOutput] as String?;

    if (path == null || locale == null) {
      return error(1, message: 'Path and locale are required.');
    }

    const ext = '.xml';
    String getName(String? argValue, String defaultName) => argValue != null
        ? (argValue.endsWith(ext) ? argValue : '$argValue$ext')
        : defaultName;

    final sourceFileName = getName(sourceName, defaultFileName);
    final outputFileName = getName(outputName, sourceFileName);

    try {
      const subPath = 'src/main/res/';
      final dir = Directory(p.join(path, subPath));

      // Track whether exported strings include xliff tags
      var needsXliffNamespace = false;

      final baseFile = getXmlFileByLocaleIfExist(
            dir,
            baseLocaleForTranslate,
            sourceFileName,
            isAndroidProject: true,
          ) ??
          getXmlFileByLocale(
            dir,
            baseLocale,
            sourceFileName,
            isAndroidProject: true,
          );
      final translationFile = getXmlFileByLocale(
        dir,
        locale,
        sourceFileName,
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
        // Detect presence of xliff tags among values to export
        needsXliffNamespace = forTranslation.any((el) =>
            el.descendants
                .whereType<XmlElement>()
                .any((d) => d.name.toString().startsWith('xliff:')));

        final xml4Translation = XmlDocument([
          XmlElement(XmlName.fromString('resources')),
        ]);
        if (needsXliffNamespace) {
          xml4Translation.resources.setAttribute(
            'xmlns:xliff',
            'urn:oasis:names:tc:xliff:document:1.2',
          );
        }
        xml4Translation.resources.children..addAll(forTranslation);

        final content = xml4Translation.toXmlString(
          pretty: true,
          indent: indent,
          entityMapping: defaultXmlEntityMapping(),
          preserveWhitespace: (node) => node.getAttribute('name') != null,
        );

        final buffer = StringBuffer();
        buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
        buffer.write(content);

        // TODO: target file path
        final targetFile = File(outputFileName);
        targetFile.writeAsStringSync(buffer.toString());

        printInfo(
            'Saved to ${targetFile.absolute.path}. Send it to translators.');
      } else {
        printInfo('Nothing to translate.');
      }

      return success(message: 'Done.');
    } on RunException catch (e) {
      return exception(e);
    } catch (e, st) {
      printVerbose('Exception: $e\n$st');
      return error(2, message: 'Failed by: $e');
    }
  }
}
