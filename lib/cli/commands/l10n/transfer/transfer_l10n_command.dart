import 'dart:io';

import 'package:list_ext/list_ext.dart';
import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

/// Command to transfer translations from one project to another.
class TransferL10nCommand extends BaseL10nCommand {
  static const _argFrom = 'from';
  static const _argTo = 'to';
  static const _argLocales = 'locales';
  static const _argFromFileName = 'filename';
  static const _argToFileName = 'to-filename';
  static const _argKeys = 'keys';

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
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final fromPath = args[_argFrom] as String?;
    final toPath = args[_argTo] as String?;
    final locales = (args[_argLocales] as String?)?.split(',');

    final fromFileName =
        getXmlFilename(args[_argFromFileName] as String?, defaultFileName);
    final toFileName =
        getXmlFilename(args[_argToFileName] as String?, fromFileName);

    final argKeys = (args[_argKeys] as String?)?.split(',');

    // TODO: move to args?
    const androidLocalesMap = {
      // '': 'en',
      // 'zh-rCN': '',
      'en': '',
    };
    const emptyLocalesMap = <String, String>{};
    const androidNonAndroidMap = <String, String>{
      'iw': 'he',
      'nb': 'no',
      'in': 'id',
      'b+sr+Latn': 'sr',
      '': 'en',
    };

    if (fromPath == null || toPath == null) {
      return error(1, message: 'Both paths are required.');
    }

    try {
      final nlNode = XmlText('\n$indent');

      final (fromDir, isFromAndroidProject) = getDir(fromPath);
      final (toDir, isToAndroidProject) = getDir(toPath);

      printVerbose(
          'Transfer from ${fromDir.path}${isFromAndroidProject ? ' [android project]' : ''} '
          'to ${toDir.path}${isToAndroidProject ? ' [android project]' : ''} ');

      printVerbose('From file: $fromFileName, to file: $toFileName');

      final fromLocalesMap = isFromAndroidProject
          ? androidLocalesMap
          : (isToAndroidProject
              ? androidNonAndroidMap.map((k, v) => MapEntry(v, k))
              : emptyLocalesMap);

      final toLocalesMap = isToAndroidProject
          ? androidLocalesMap
          : (isFromAndroidProject ? androidNonAndroidMap : emptyLocalesMap);

      final keysMap = <String, String>{};
      final keys = argKeys?.map((k) {
            final parts = k.split('=');
            final res = parts.first;
            if (parts.length == 2) keysMap[res] = parts[1];
            return res;
          }) ??
          await _getAllKeys(
              fromDir, toDir, fromFileName, toFileName, fromLocalesMap,
              validateByBase: locales != null);

      printVerbose('Keys for transfer: ${keys.join(', ')}.');

      final changedLocales = <String>{};
      await forEachStringsFile(fromDir, fromFileName,
          (dirName, file, locale) async {
        final String toDirName;
        final String toLocale;

        printVerbose('Checking from file ${file.path} [$locale]');

        if (toLocalesMap.containsKey(locale)) {
          toLocale = toLocalesMap[locale]!;
          toDirName =
              isToAndroidProject ? getDirNameByLocale(toLocale) : toLocale;
        } else {
          // TODO: basically we need to check separator, it may be "-" and if this is not android project
          // "-r" very unreliable too. Maybe we can check for existence with fallbacks
          if (isFromAndroidProject == isToAndroidProject) {
            toLocale = locale;
          } else if (isFromAndroidProject) {
            toLocale = locale.replaceAll('-r', '_').replaceAll('-', '_');
          } else {
            toLocale = locale.replaceAll('_', '-r');
          }

          toDirName = isToAndroidProject ? dirName : toLocale;
        }

        if (locales != null && !locales.contains(toLocale)) return;

        final toFile = getXmlFile(toDir, toDirName, toFileName);

        printVerbose('Checking to file ${toFile.path} [$toLocale]');
        if (!toFile.existsSync()) {
          printVerbose('Not found, skipping');
          return;
        }

        printVerbose('Processing $locale...');

        final fromXml = await _loadXml(file);
        final toXml = await _loadXml(toFile);

        final toResources = toXml.resources.children;
        final lastTextNode = toResources.removeLast();

        final added = <XmlElement>{};
        final changed = <XmlElement>{};
        fromXml.forEachResource((child) {
          if (!['string'].contains(child.name.toString())) return;
          final name = child.attributeName;
          if (keys.contains(name)) {
            final value = _cleanValue(child.innerText);

            final newName = keysMap.containsKey(name) ? keysMap[name]! : name;
            final currentNode = toResources
                .whereType<XmlElement>()
                .firstWhereOrNull((c) => c.attributeName == newName);
            if (currentNode == null) {
              printVerbose('Add <$newName>: $value');
              final newNode = child.copy();
              newNode.attributeName = newName;
              newNode.innerText = value;

              // clean
              newNode.removeAttribute('msgid');

              toResources
                ..add(nlNode.copy())
                ..add(newNode);

              added.add(newNode);
            } else if (currentNode.innerText != value) {
              printVerbose(
                  'Change <$newName>: ${currentNode.innerText} -> $value');
              changed.add(child);
              currentNode.innerText = value;
            } else {
              printVerbose(
                  'Key <$newName> already exist, skipping, <${currentNode.innerText}>, <$value> [$locale]');
            }
          }
        });
        toResources.add(lastTextNode);

        if (added.isNotEmpty || changed.isNotEmpty) {
          changedLocales.add(toLocale);
          printInfo('${toFile.path}: ${[
            if (added.isNotEmpty) 'added: ${added.length}',
            if (changed.isNotEmpty) 'changed: ${changed.length}',
          ].join(', ')}');
          await toFile.writeAsString(toXml.toXmlString(
            // pretty: true,
            // indent: indent,
            //preserveWhitespace: (n) => !added.contains(n),
            entityMapping: defaultXmlEntityMapping(),
          ));
        } else {
          printVerbose('Nothing');
        }
      }, isAndroidProject: isFromAndroidProject);

      if (changedLocales.isNotEmpty) {
        printInfo('\nChanged ${changedLocales.length} locales: '
            '${(changedLocales.toList()..sort()).join(', ')}.');
      } else {
        printInfo('No changes');
      }

      return success(message: 'Done.');
    } on RunException catch (e) {
      return exception(e);
    } catch (e, st) {
      printVerbose('Exception: $e\n$st');
      return error(2, message: 'Failed by: $e');
    }
  }

  Future<XmlDocument> _loadXml(File file) async {
    try {
      return XmlDocument.parse(await file.readAsString());
    } catch (e, st) {
      printVerbose('Exception during load xml from ${file.path}: $e\n$st');
      throw RunException.err('Failed load XML ${file.path}: $e');
    }
  }

  Future<List<String>> _getAllKeys(
    Directory fromDir,
    Directory toDir,
    String fromFileName,
    String toFileName,
    Map<String, String> localesMap, {
    bool validateByBase = false,
  }) async {
    final fromLocale = baseLocale;
    final toLocale =
        validateByBase ? (localesMap[fromLocale] ?? baseLocale) : baseLocale;
    final fromMap = await loadValuesByKeys(
        getXmlFileByLocale(fromDir, fromLocale, fromFileName));
    final toMap =
        await loadValuesByKeys(getXmlFileByLocale(toDir, toLocale, toFileName));
    return toMap.keys.where((key) {
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

  (Directory, bool) getDir(String mainPath) {
    const subPath = 'src/main/res/';
    final dirForAndroidProject = Directory(p.join(mainPath, subPath));
    if (dirForAndroidProject.existsSync()) return (dirForAndroidProject, true);

    const subPath2 = 'res/';
    final dirForAndroidProject2 = Directory(p.join(mainPath, subPath2));
    if (File(p.join(dirForAndroidProject2.path, 'values/strings.xml'))
        .existsSync()) {
      return (dirForAndroidProject2, true);
    }

    return (Directory(mainPath), false);
  }

  String _cleanValue(String value) {
    var res = value;
    if (value.startsWith('"') && value.endsWith('"')) {
      res = res.substring(1, res.length - 1);
    }
    return res;
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
