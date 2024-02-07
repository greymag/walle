import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

/// Command to export  keys and values to Google Docs (sheets).
class GoolgedocExportL10nCommand extends BaseL10nCommand {
  static const _argTo = 'to';
  static const _argPath = 'path';

  GoolgedocExportL10nCommand()
      : super(
          'googledoc',
          'Export keys and values to Google Docs (sheet).',
        ) {
    argParser
      ..addOption(
        _argTo,
        abbr: 't',
        help: 'Google Sheet url.',
        valueHelp: 'URL',
      )
      ..addOption(
        _argPath,
        abbr: 'p',
        help: 'Project path.',
        valueHelp: 'PATH',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final toUrl = args[_argTo] as String?;
    final path = args[_argPath] as String?;
    // TODO: add argument
    final fileName = defaultFileName;

    if (toUrl == null || path == null) {
      return error(1, message: 'Path and URL are required.');
    }

    try {
      const subPath = 'src/main/res/'; // TODO: вынести
      final dir = Directory(p.join(path, subPath));

      // TODO:
      // printVerbose('Connecting to Google Docs...');
      // final api = await _connectGoogleDocs();
      // if (api == null) {
      //   return error(1, message: 'Failed to connect to Google Docs.');
      // }
      // printVerbose('Connected.');

      // printVerbose('Load $toUrl');
      // final document = await api.loadDocument(toUrl);
      // printVerbose('Document loaded, ${document.sheets?.length} sheets');

      // TODO: sheet as arg of get from url
      // final sheet = document.sheets!.first;
      // printVerbose('Selected sheet: ${sheet.properties?.title}');

      final baseFile =
          getXmlFileByLocaleIfExist(dir, baseLocaleForTranslate, fileName) ??
              getXmlFileByLocale(dir, baseLocale, fileName);
      final baseXml = await loadXml(baseFile);

      // TODO: only if not exist in google doc (or maybe update value for all with difference)

      baseXml.forEachResource((child) {
        final key = child.attributeName;
        final value = child.innerText;

        // TODO: write in google doc
        print('$key\t$value');
      });

      return success(message: 'Done');
    } on RunException catch (e) {
      return exception(e);
    } catch (e, st) {
      printVerbose('Exception: $e\n$st');
      return error(2, message: 'Failed by: $e');
    }
  }

  // Future<GoogleSheetsApi?> _connectGoogleDocs() async {
  //   final client = GoogleSheetsApi(printInfo, log: printVerbose);
  //   return await client.connect() ? client : null;
  // }
}
