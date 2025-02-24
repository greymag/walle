import 'dart:io';

import 'package:list_ext/list_ext.dart';
import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:walle/src/locales/lang_codes.dart';

/// Commands to import localization.
class ImportL10nCommand extends BaseL10nCommand {
  static const _argFrom = 'from';
  static const _argPath = 'path';
  // static const _argLocale = 'locale';
  static const _argTargetFileName = 'target-file';

  ImportL10nCommand()
      : super(
          'import',
          'Import translations from the directory to the Android project.',
        ) {
    argParser
      ..addOption(
        _argFrom,
        abbr: 'f',
        help: 'Translations directory path.',
        valueHelp: 'PATH',
        mandatory: true,
      )
      ..addOption(
        _argPath,
        abbr: 'p',
        help: 'Project path.',
        valueHelp: 'PATH',
        mandatory: true,
      )
      ..addOption(
        _argTargetFileName,
        abbr: 't',
        help: 'Target file name.',
        valueHelp: 'NAME',
        defaultsTo: defaultFileName,
      );
    // ..addOption(
    //   _argLocale,
    //   abbr: 'l',
    //   help: 'Locale to import.',
    //   valueHelp: 'LOCALE',
    // );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final fromPath = args[_argFrom] as String?;
    final projectPath = args[_argPath] as String?;
    final targetFileName =
        (args[_argTargetFileName] as String?) ?? defaultFileName;
    // TODO: support locale argument
    // final locale = args[_argLocale] as String?;

    if (projectPath == null || fromPath == null) {
      return error(
        1,
        message: 'Arguments --$_argFrom and --$_argPath are required.',
      );
    }

    try {
      const subPath = 'src/main/res/';
      final targetDir = Directory(p.join(projectPath, subPath));

      if (!targetDir.existsSync()) {
        return error(2,
            message: 'Project directory ${targetDir.absolute.path} not found.');
      }

      final baseFile = getXmlFileByLocaleIfExist(
            targetDir,
            baseLocaleForTranslate,
            targetFileName,
            isAndroidProject: true,
          ) ??
          getXmlFileByLocale(
            targetDir,
            baseLocale,
            targetFileName,
            isAndroidProject: true,
          );

      if (!baseFile.existsSync()) {
        return error(
          2,
          message: 'Base file ${baseFile.absolute.path} not found.',
        );
      }

      final sourceDir = Directory(fromPath);
      if (!sourceDir.existsSync()) {
        return error(
          2,
          message: 'Source directory ${sourceDir.absolute.path} not found.',
        );
      }

      // Get all keys from the base file
      final keys = (await loadValuesByKeys(baseFile)).keys.toSet();

      // Prepare target files data
      final targetFiles = <String, File>{};
      await forEachStringsFile(
        targetDir,
        targetFileName,
        (dirName, file, locale) async {
          targetFiles[locale] = file;
        },
        isAndroidProject: true,
      );
      printVerbose('Found ${targetFiles.length} target files.');

      final expectedLocales = targetFiles.keys
          .where((l) =>
              l != baseLocale &&
              l != baseLocaleForTranslate &&
              !notTranslatableLocales.contains(l))
          .toSet();

      const separators = ['-r', '-', '_'];
      String normalizeLocale(String locale) =>
          separators.fold(locale, (res, sep) => res.replaceAll(sep, ''));

      String? lookupTargetLocale(String locale) {
        String? check(String l) => targetFiles.containsKey(l) ? l : null;

        String? checkCompat(String l) {
          // try compatible
          final compatMap = {'no': 'nb'};
          final compatLocale = compatMap[l];

          var res = compatLocale != null ? check(compatLocale) : null;
          if (res != null) return res;

          // convert 3 letter to 2 letter
          if (l.length == 3) {
            final lang = LangCodes.getByAlpha3(l);
            final alpha2Code = lang?.alpha2.toLowerCase();

            res = alpha2Code != null ? check(alpha2Code) : null;
            if (res != null) return res;
          }

          return null;
        }

        var res = check(locale);
        if (res != null) return locale;

        for (final sep in separators) {
          if (!locale.contains(sep)) continue;

          for (final altSep in separators) {
            if (sep == altSep) continue;

            res = check(locale.replaceFirst(sep, altSep));
            if (res != null) return res;
          }

          final baseLocale = locale.substring(0, locale.indexOf(sep));
          res = check(baseLocale) ?? checkCompat(baseLocale);
          if (res != null) return res;
        }

        return checkCompat(locale);
      }

      // Import from the directory
      printVerbose('Import from ${sourceDir.path}');

      final changedLocales = <String>{};
      final processedLocales = <String>{};
      var totalStat = XmlTransferStat();

      final sourceFiles = sourceDir.listSync().whereType<File>().toList()
        ..sortBy((f) => p.basename(f.path));

      for (final sourceFile in sourceFiles) {
        if (p.extension(sourceFile.path) == '.xml') {
          final sourceFullFileName = p.basename(sourceFile.path);
          printInfo('Import $sourceFullFileName');

          final sourceFileName = p.basenameWithoutExtension(sourceFile.path);
          final sourceLocale = _getLocaleFromFileName(sourceFileName);

          printVerbose(' > Locale: $sourceLocale');

          if (sourceLocale.isEmpty) {
            throw RunException.err(
                'Locale not found in the file name $sourceFullFileName');
          }

          final targetLocale = lookupTargetLocale(sourceLocale);
          if (targetLocale == null) {
            throw RunException.err(
                'Cannot find target file for locale $sourceLocale. Source file: $sourceFullFileName.\n'
                'If this is a new locale, please add it to the project first.');
          }

          if (normalizeLocale(sourceLocale) != normalizeLocale(targetLocale)) {
            printInfo(' * Auto match locale: $sourceLocale -> $targetLocale');
          }

          if (!expectedLocales.contains(targetLocale)) {
            throw RunException.warn(
                'Locale $targetLocale is not expected for translation import. '
                'Source file: $sourceFullFileName');
          }

          final targetFile = targetFiles[targetLocale]!;
          printVerbose(' > Target: ${targetFile.path}');
          processedLocales.add(targetLocale);

          final sourceXml = await loadXml(sourceFile);
          final targetXml = await loadXml(targetFile);

          final (:added, :changed, :stat) = transferStrings(
            sourceXml,
            targetXml,
            allowedKeys: keys,
            outIndent: ' * ',
          );

          totalStat += stat;

          if (added.isNotEmpty || changed.isNotEmpty) {
            changedLocales.add(targetLocale);

            if (added.isNotEmpty) {
              printVerbose(' # Added: ${added.length}');
            }

            if (changed.isNotEmpty) {
              printVerbose(' # Changed: ${changed.length}');
            }

            await writeXml(targetFile, targetXml);
          } else {
            printVerbose('# Nothing');
          }
          printVerbose('--');
        } else {
          printVerbose('Skip ${sourceFile.path}');
        }
      }

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

  String _getLocaleFromFileName(String fileName) {
    final baseName = p.basenameWithoutExtension(fileName);
    final index = baseName.indexOf('_');
    return baseName.substring(index + 1);
  }
}
