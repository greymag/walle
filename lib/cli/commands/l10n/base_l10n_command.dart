import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/walle_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

const _dirPrefix = 'values';
const _baseLocale = '';
const _fileName = 'strings.xml';
const _indent = '    ';
const _baseLocaleForTranslate = 'en';

abstract class BaseL10nCommand extends WalleCommand {
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
  String get fileName => _fileName;

  @protected
  String get baseLocale => _baseLocale;

  @protected
  String get baseLocaleForTranslate => _baseLocaleForTranslate;

  @protected
  String getXmlPath(Directory baseDir, String subdirName) =>
      p.join(baseDir.path, subdirName, _fileName);

  @protected
  File getXmlFile(Directory baseDir, String subdirName) =>
      File(getXmlPath(baseDir, subdirName));

  @protected
  String getXmlPathByLocale(Directory baseDir, String locale) =>
      getXmlPath(baseDir, getDirNameByLocale(locale));

  @protected
  File getXmlFileByLocale(Directory baseDir, String locale) =>
      File(getXmlPathByLocale(baseDir, locale));

  @protected
  File? getXmlFileByLocaleIfExist(Directory baseDir, String locale) {
    final file = getXmlFileByLocale(baseDir, locale);
    return file.existsSync() ? file : null;
  }

  @protected
  String getDirNameByLocale(String locale) =>
      locale.isNotEmpty ? '$_dirPrefix-$locale' : _dirPrefix;

  @protected
  Future<Map<String, String>> loadValuesByKeys(File file) async {
    final xml = await loadXml(file);
    final data = <String, String>{};
    xml.forEachResource((child) {
      data[child.attributeName] = child.text;
    });

    return data;
  }

  @protected
  XmlEntityMapping defaultXmlEntityMapping() => _XmlEntityMapping();

  @protected
  Future<void> forEachStringsFile(
    Directory dir,
    Future<void> Function(String dirName, File file, String locale) callback,
  ) async {
    await for (final d in dir.list()) {
      if (d is! Directory) continue;

      final dirName = p.basename(d.path);
      if (dirName.startsWith(dirPrefix)) {
        final fromDirName = dirName;
        final fromFile = getXmlFile(dir, fromDirName);
        if (!fromFile.existsSync()) continue;

        final prefixEndIndex = dirName.indexOf('-');
        final locale = prefixEndIndex != -1
            ? dirName.substring(prefixEndIndex + 1)
            : baseLocale;

        await callback(dirName, fromFile, locale);
      }
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
