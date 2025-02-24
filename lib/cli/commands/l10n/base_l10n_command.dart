import 'dart:io';

import 'package:list_ext/list_ext.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/walle_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

const _dirPrefix = 'values';
const _baseLocale = '';
const _baseLocaleValue = 'en';
const _defaultFileName = 'strings.xml';
const _indent = '    ';
const _baseLocaleForTranslate = 'en';
const _kNotTranslatableLocales = {'ru'};

const _kTypeString = 'string';
const _kTypeStringArray = 'array';
const _kTypePlurals = 'plurals';

abstract class BaseL10nCommand extends WalleCommand {
  static final _escapeSingleQuote = RegExp(r"(?<!\\)'");

  BaseL10nCommand(String name, String description,
      {List<WalleCommand>? subcommands})
      : super(name, description, subcommands: subcommands);

  @protected
  Future<XmlDocument> loadXml(File file) async {
    try {
      return XmlDocument.parse(await file.readAsString());
    } catch (e, st) {
      printVerbose('Exception during load xml from ${file.path}: $e\n$st');
      throw RunException.err('Failed load XML ${file.path}: $e');
    }
  }

  @protected
  String get indent => _indent;

  @protected
  String get dirPrefix => _dirPrefix;

  @protected
  String get defaultFileName => _defaultFileName;

  @protected
  String get baseLocale => _baseLocale;

  @protected
  String get baseLocaleForTranslate => _baseLocaleForTranslate;

  @protected
  Set<String> get notTranslatableLocales => _kNotTranslatableLocales;

  @protected
  String getXmlPath(Directory baseDir, String subdirName, String fileName) =>
      p.join(baseDir.path, subdirName, fileName);

  @protected
  File getXmlFile(Directory baseDir, String subdirName, String fileName) =>
      File(getXmlPath(baseDir, subdirName, fileName));

  @protected
  String getXmlPathByLocale(
    Directory baseDir,
    String locale,
    String fileName, {
    required bool isAndroidProject,
  }) =>
      getXmlPath(
        baseDir,
        getDirNameByLocale(locale, isAndroidProject: isAndroidProject),
        fileName,
      );

  @protected
  File getXmlFileByLocale(
    Directory baseDir,
    String locale,
    String fileName, {
    required bool isAndroidProject,
  }) =>
      File(getXmlPathByLocale(
        baseDir,
        locale,
        fileName,
        isAndroidProject: isAndroidProject,
      ));

  @protected
  File? getXmlFileByLocaleIfExist(
    Directory baseDir,
    String locale,
    String fileName, {
    required bool isAndroidProject,
  }) {
    final file = getXmlFileByLocale(
      baseDir,
      locale,
      fileName,
      isAndroidProject: isAndroidProject,
    );
    return file.existsSync() ? file : null;
  }

  @protected
  String getDirNameByLocale(
    String locale, {
    required bool isAndroidProject,
  }) =>
      isAndroidProject
          ? (locale.isNotEmpty ? '$_dirPrefix-$locale' : _dirPrefix)
          : (locale.isNotEmpty ? locale : _baseLocaleValue);

  @protected
  Future<Map<String, String>> loadValuesByKeys(File file) async {
    final xml = await loadXml(file);
    final data = <String, String>{};
    xml.forEachResource((child) {
      data[child.attributeName] = child.value ?? '';
    });

    return data;
  }

  @protected
  XmlEntityMapping defaultXmlEntityMapping() => _XmlEntityMapping();

  @protected
  Future<void> forEachStringsFile(
    Directory dir,
    String fileName,
    Future<void> Function(String dirName, File file, String locale) callback, {
    bool isAndroidProject = true,
  }) async {
    printVerbose('Process dir ${dir.path}');
    var processed = 0;
    await for (final d in dir.list()) {
      if (d is! Directory) continue;

      final prefix = isAndroidProject ? dirPrefix : '';
      final dirName = p.basename(d.path);
      if (prefix.isEmpty || dirName.startsWith(prefix)) {
        // printVerbose('Process dir ./$dirName');
        final fromDirName = dirName;
        final fromFile = getXmlFile(dir, fromDirName, fileName);
        // printVerbose('Check ${fromFile.path}');
        if (!fromFile.existsSync()) continue;

        final String locale;
        if (isAndroidProject) {
          final prefixEndIndex = dirName.indexOf('-');
          locale = prefixEndIndex != -1
              ? dirName.substring(prefixEndIndex + 1)
              : baseLocale;
        } else {
          locale = dirName;
        }

        processed++;
        await callback(dirName, fromFile, locale);
      } else {
        // printVerbose('Skip dir ./$dirName');
      }
    }

    if (processed == 0) {
      printInfo('No files or directory processed. '
          'Check path, it should point to the android app directory '
          'or explicitly to the translations directory.');
    }
  }

  @protected
  String getXmlFilename(String? name, String defaultName) {
    final res = name ?? defaultName;
    const ext = '.xml';
    return p.extension(res) == ext ? res : p.setExtension(res, ext);
  }

  @protected
  ({
    Set<XmlElement> added,
    Set<XmlElement> changed,
    XmlTransferStat stat,
  }) transferStrings(
    XmlDocument fromXml,
    XmlDocument toXml, {
    Iterable<XmlFileType>? supportedTypes,
    Iterable<String>? neededKeys,
    Iterable<String>? allowedKeys,
    Map<String, int>? arrayIndexByKey,
    Map<String, String>? keysMap,
    XmlFileType? toType,
    String outIndent = '',
  }) {
    final toResources = toXml.resources.children;
    final lastTextNode = toResources.removeLast();

    final allowedTags = supportedTypes?.map((e) => e.tag).toSet();

    final nlNode = XmlText('\n$indent');

    final added = <XmlElement>{};
    final changed = <XmlElement>{};
    var skippedEntries = 0;
    fromXml.forEachResource((child) {
      final tag = child.name.toString();
      if (allowedTags?.contains(tag) == false) return;

      final name = child.attributeName;
      final nodeType = XmlFileType.tryByTag(tag);
      if (nodeType == null) {
        throw RunException.err('Unsupported tag <$tag> for key <$name>.\n'
            'Supported tags: ${XmlFileType.tags.join(', ')}');
      }

      if (neededKeys?.contains(name) == false) {
        return;
      }

      if (allowedKeys?.contains(name) == false) {
        printInfo('${outIndent}Skip key <$name>, because it is not allowed');
        skippedEntries++;
        return;
      }

      final String value;
      try {
        switch (nodeType) {
          case XmlFileType.string:
            {
              value = _cleanValue(child.getValue());
            }
          case XmlFileType.stringArray:
            {
              // TODO: currently only supports transfer one of the array element to the target string
              final indexInArray = arrayIndexByKey?[name];
              if (indexInArray == null) {
                throw Exception('Transfer full array is not implemented yet. '
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
          case XmlFileType.plurals:
            {
              value = child.getValue();
            }
        }
      } catch (e, st) {
        throw RunException.err('Failed to get value for key <$name>: $e\n$st');
      }

      final newName = keysMap != null && keysMap.containsKey(name) == true
          ? keysMap[name]!
          : name;

      final currentNode = toResources
          .whereType<XmlElement>()
          .firstWhereOrNull((c) => c.attributeName == newName);
      final curValue = currentNode?.getValue();
      if (curValue == null) {
        printVerbose('${outIndent}Add <$newName>: $value');
        // final newNode = child.copy();
        final toTag = toType?.tag ?? tag;
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
        printVerbose('${outIndent}Change <$newName>: $curValue -> $value');
        changed.add(child);
        currentNode!.setValue(value);
      } else {
        printVerbose(
            '${outIndent}Key <$newName> already exist, skipping, <$curValue>, <$value>');
      }
    });
    toResources.add(lastTextNode);

    return (
      added: added,
      changed: changed,
      stat: XmlTransferStat(
        skippedEntries: skippedEntries,
      ),
    );
  }

  String _cleanValue(String value) {
    var res = value;
    if (value.startsWith('"') && value.endsWith('"')) {
      res = res.substring(1, res.length - 1);
    }

    // replace "'" with "\'" if not already escaped
    return res.replaceAll(_escapeSingleQuote, r"\'");
  }

  @protected
  (Directory, bool) getResDir(String mainPath, XmlFileType type) {
    const subPath = 'src/main/res/';
    final dirForAndroidProject = Directory(p.join(mainPath, subPath));
    if (dirForAndroidProject.existsSync()) return (dirForAndroidProject, true);

    const subPath2 = 'res/';
    final dirForAndroidProject2 = Directory(p.join(mainPath, subPath2));

    final androidProjectSubPath = switch (type) {
      XmlFileType.string => 'values/strings.xml',
      XmlFileType.stringArray => 'values/arrays.xml',
      XmlFileType.plurals =>
        'values/plurals.xml', // TODO: or maybe strings.xml?
    };

    if (File(p.join(dirForAndroidProject2.path, androidProjectSubPath))
        .existsSync()) {
      return (dirForAndroidProject2, true);
    }

    return (Directory(mainPath), false);
  }

  @protected
  Future<void> writeXml(File file, XmlDocument xml) async {
    await file.writeAsString(xml.toXmlString(
      // pretty: true,
      // indent: indent,
      //preserveWhitespace: (n) => !added.contains(n),
      entityMapping: defaultXmlEntityMapping(),
    ));
  }

  void printSummary(
    Set<String> changedLocales,
    Set<String> processedLocales,
    Set<String> expectedLocales,
    XmlTransferStat stat,
  ) {
    if (changedLocales.isNotEmpty) {
      printInfo('\n📝 Changed ${changedLocales.length} locales: '
          '${(changedLocales.toList()..sort()).join(', ')}.');
    } else {
      printInfo('🔍 No changes');
    }

    if (stat.skippedEntries > 0) {
      printInfo('❗ Skipped ${stat.skippedEntries} entries. See output above.');
    }

    if (processedLocales.length < expectedLocales.length) {
      printInfo('⚠️ Warning! Expected ${expectedLocales.length} locales, '
          'processed ${processedLocales.length}');
      printInfo(
          'ℹ️ Skipped locales: ${expectedLocales.where((l) => !processedLocales.contains(l)).join(', ')}');
    } else {
      printInfo(
          '✅ Processed ${processedLocales.length} locales (expected ${expectedLocales.length}).');
    }
  }
}

extension XmlDocumentExtension on XmlDocument {
  XmlElement get resources => findAllElements('resources').first;

  void forEachResource(void Function(XmlElement child) callback) {
    for (final child in resources.children) {
      if (child is XmlElement) callback(child);
    }
  }
}

extension XmlElementExtension on XmlElement {
  String get attributeName => getAttribute('name')!;
  set attributeName(String value) => setAttribute('name', value);
  // String getValue() => innerText;
  String getValue() => innerXml;
  void setValue(String value) {
    // innerText = value;
    innerXml = value;
  }
}

class _XmlEntityMapping extends XmlDefaultEntityMapping {
  _XmlEntityMapping() : super.xml();

  @override
  String encodeText(String input) {
    return super
        .encodeText(input)
        .replaceAll('>', '&gt;')
        .replaceAll('\r', '&#13;')
        .replaceAll('🀄', '&#126980;')
        .replaceAll('&#x7F;', '&#127;');
  }
}

enum XmlFileType {
  string(_kTypeString),
  stringArray(_kTypeStringArray),
  plurals(_kTypePlurals);

  static XmlFileType byName(String value) =>
      XmlFileType.values.firstWhere((e) => e.name == value);

  static XmlFileType? tryByName(String value) =>
      XmlFileType.values.firstWhereOrNull((e) => e.name == value);

  static XmlFileType? tryByTag(String value) =>
      XmlFileType.values.firstWhereOrNull((e) => e.tag == value);

  static List<String> get names =>
      XmlFileType.values.map((e) => e.name).toList();

  static List<String> get tags => XmlFileType.values.map((e) => e.tag).toList();

  final String name;

  const XmlFileType(this.name);

  String get tag => switch (this) {
        XmlFileType.string => 'string',
        XmlFileType.stringArray => 'string-array',
        XmlFileType.plurals => 'plurals',
      };
}

class XmlTransferStat {
  final int skippedEntries;

  XmlTransferStat({
    this.skippedEntries = 0,
  });

  XmlTransferStat operator +(XmlTransferStat other) => XmlTransferStat(
        skippedEntries: skippedEntries + other.skippedEntries,
      );
}
