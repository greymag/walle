import 'dart:io';

import 'package:list_ext/list_ext.dart';
import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

const _kTypeString = 'string';
const _kTypeStringArray = 'array';

/// Command to transfer translations from one project to another.
class TransferL10nCommand extends BaseL10nCommand {
  static const _argFrom = 'from';
  static const _argTo = 'to';
  static const _argLocales = 'locales';
  static const _argFromFileName = 'filename';
  static const _argToFileName = 'to-filename';
  static const _argKeys = 'keys';
  static const _argFromType = 'from-type';

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
      )
      ..addOption(
        _argFromType,
        help: 'Name of the file to work with',
        valueHelp: 'my_filename',
        defaultsTo: _kTypeString,
        allowed: [_kTypeString, _kTypeStringArray],
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final fromPath = args[_argFrom] as String?;
    final toPath = args[_argTo] as String?;
    final locales = (args[_argLocales] as String?)?.split(',');
    final fromType = _FileType.byName(args[_argFromType]! as String);

    final fromFileName =
        getXmlFilename(args[_argFromFileName] as String?, defaultFileName);
    final toFileName =
        getXmlFilename(args[_argToFileName] as String?, fromFileName);

    final argKeys = (args[_argKeys] as String?)?.split(',');

    const toType = _FileType.string;

    // TODO: move to args?
    const androidLocalesMap = {
      // '': 'en',
      // 'zh-rCN': '',
      'en': '',
    };
    const emptyLocalesMap = <String, String>{};
    const android2NonAndroidMap = <String, String>{
      'iw': 'he',
      'nb': 'no',
      'in': 'id',
      'b+sr+Latn': 'sr',
      '': 'en',
    };

    final nonAndroid2AndroidMap =
        android2NonAndroidMap.map((k, v) => MapEntry(v, k));

    if (fromPath == null || toPath == null) {
      return error(1, message: 'Both paths are required.');
    }

    try {
      final nlNode = XmlText('\n$indent');

      final (fromDir, isFromAndroidProject) = getDir(fromPath, fromType);
      final (toDir, isToAndroidProject) = getDir(toPath, toType);

      printVerbose(
          'Transfer from ${fromDir.path}${isFromAndroidProject ? ' [android project]' : ''} '
          'to ${toDir.path}${isToAndroidProject ? ' [android project]' : ''} ');

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
            if (fromType == _FileType.stringArray && fromKey.contains('[')) {
              final keyParts =
                  fromKey.substring(0, fromKey.length - 1).split('[');
              fromKey = keyParts[0];
              arrayIndexByKey[fromKey] = int.parse(keyParts[1]);
            }

            if (parts.length == 2) keysMap[fromKey] = parts[1];
            return fromKey;
          }) ??
          await _getAllKeys(
              fromDir, toDir, fromFileName, toFileName, fromLocalesMap,
              validateByBase: locales != null);

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

      File? lookupImportFile(String locale) {
        final file = importData[locale];
        if (file != null) return file;
        printVerbose('Not found file for $locale, try fallback');
        if (locale.contains('-')) {
          return lookupImportFile(locale.substring(0, locale.indexOf('-')));
        } else if (locale.contains('_')) {
          return lookupImportFile(locale.substring(0, locale.indexOf('_')));
        }
        return null;
      }

      final fromTag = fromType.tag;
      final toTag = toType.tag;

      final expectedLocales = <String>{};
      final processedLocales = <String>{};
      final changedLocales = <String>{};

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

          print('toLocalesMap:$toLocalesMap');

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

          final fromXml = await _loadXml(fromFile);
          final toXml = await _loadXml(toFile);

          final toResources = toXml.resources.children;
          final lastTextNode = toResources.removeLast();

          final added = <XmlElement>{};
          final changed = <XmlElement>{};
          fromXml.forEachResource((child) {
            if (![fromTag].contains(child.name.toString())) return;
            final name = child.attributeName;
            if (!keys.contains(name)) return;

            final String value;

            switch (fromType) {
              case _FileType.string:
                {
                  value = _cleanValue(child.getValue());
                }
              case _FileType.stringArray:
                {
                  final indexInArray = arrayIndexByKey[name];
                  if (indexInArray == null) {
                    throw Exception(
                        'Transfer full array is not implemented yet. '
                        'Specify index of the element in array in key name like: key[index]');
                  }

                  final item = child.childElements
                      .where((e) => e.name.toString() == 'item')
                      .elementAtOrNull(indexInArray);

                  if (item == null) {
                    throw RunException.err(
                        'Cannot find item with index [$indexInArray] for array with key "$name"');
                  }

                  value = _cleanValue(item.getValue());
                }
            }

            final newName = keysMap.containsKey(name) ? keysMap[name]! : name;
            final currentNode = toResources
                .whereType<XmlElement>()
                .firstWhereOrNull((c) => c.attributeName == newName);
            final curValue = currentNode?.getValue();
            if (curValue == null) {
              printVerbose('Add <$newName>: $value');
              // final newNode = child.copy();
              final newNode = XmlElement.tag(toTag);
              newNode.attributeName = newName;
              // newNode.innerText = value;
              newNode.setValue(value);

              // clean
              // newNode.removeAttribute('msgid');

              toResources
                ..add(nlNode.copy())
                ..add(newNode);

              added.add(newNode);
            } else if (curValue != value) {
              printVerbose('Change <$newName>: $curValue -> $value');
              changed.add(child);
              currentNode!.setValue(value);
            } else {
              printVerbose(
                  'Key <$newName> already exist, skipping, <$curValue>, <$value> [$locale]');
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
        },
        isAndroidProject: isToAndroidProject,
      );

      if (changedLocales.isNotEmpty) {
        printInfo('\nChanged ${changedLocales.length} locales: '
            '${(changedLocales.toList()..sort()).join(', ')}.');
      } else {
        printInfo('No changes');
      }

      if (processedLocales.length < expectedLocales.length) {
        printInfo('Warning! Expected ${expectedLocales.length} locales, '
            'processed ${processedLocales.length}');
        printInfo(
            'Skipped locales: ${expectedLocales.where((l) => !processedLocales.contains(l)).join(', ')}');
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

  (Directory, bool) getDir(String mainPath, _FileType type) {
    const subPath = 'src/main/res/';
    final dirForAndroidProject = Directory(p.join(mainPath, subPath));
    if (dirForAndroidProject.existsSync()) return (dirForAndroidProject, true);

    const subPath2 = 'res/';
    final dirForAndroidProject2 = Directory(p.join(mainPath, subPath2));

    final androidProjectSubPath = switch (type) {
      _FileType.string => 'values/strings.xml',
      _FileType.stringArray => 'values/arrays.xml',
    };

    if (File(p.join(dirForAndroidProject2.path, androidProjectSubPath))
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

extension _XmlElementExt on XmlElement {
  // String getValue() => innerText;
  String getValue() => innerXml;
  void setValue(String value) {
    // innerText = value;
    innerXml = value;
  }
}

enum _FileType {
  string(_kTypeString),
  stringArray(_kTypeStringArray);

  static _FileType byName(String value) =>
      _FileType.values.firstWhere((e) => e.name == value);

  final String name;

  const _FileType(this.name);

  String get tag => switch (this) {
        _FileType.string => 'string',
        _FileType.stringArray => 'string-array'
      };
}
