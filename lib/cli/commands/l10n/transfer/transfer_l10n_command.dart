import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/walle_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

const _dirPrefix = 'values';
const _baseLocaleForTranslations = 'en';
const _fileName = 'strings.xml';

/// Command to export summary data from all account.
class TransferL10nCommand extends WalleCommand {
  static const _argFrom = 'from';
  static const _argTo = 'to';
  static const _argLocales = 'locales';
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
            'presented at main locale will be transferred.',
        valueHelp: 'key1,key2,...',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final fromPath = args[_argFrom] as String?;
    final toPath = args[_argTo] as String?;
    final locales = (args[_argLocales] as String?)?.split(',');

    final argKeys = (args[_argKeys] as String?)?.split(',');

    // TODO: move to args?
    const localesMap = {
      '': 'en',
      'zh-rCN': '',
    };

    if (fromPath == null || toPath == null) {
      return error(1, message: 'Both paths are required.');
    }

    try {
      const subPath = 'src/main/res/';
      const indent = '    ';
      final nlNode = XmlText('\n$indent');

      final fromDir = Directory(p.join(fromPath, subPath));
      final toDir = Directory(p.join(toPath, subPath));

      final keys = argKeys ?? await _getAllKeys(fromDir, toDir, localesMap);
      await for (final d in fromDir.list()) {
        final dirName = p.basename(d.path);
        if (dirName.startsWith(_dirPrefix)) {
          final fromDirName = dirName;
          final fromFile = _getXmlFile(fromDir, fromDirName);
          if (!fromFile.existsSync()) continue;

          final String toDirName;
          final String toLocale;

          final prefixEndIndex = dirName.indexOf('-');
          final locale =
              prefixEndIndex != -1 ? dirName.substring(prefixEndIndex + 1) : '';

          if (localesMap.containsKey(locale)) {
            toLocale = localesMap[locale]!;
            toDirName = _getDirNameByLocale(toLocale);
          } else {
            toLocale = locale;
            toDirName = dirName;
          }

          if (locales != null && !locales.contains(toLocale)) continue;

          final toFile = _getXmlFile(toDir, toDirName);
          if (!toFile.existsSync()) continue;

          final fromXml = await _loadXml(fromFile);
          final toXml = await _loadXml(toFile);

          final toResources = toXml.resources.children;
          final lastTextNode = toResources.removeLast();

          final added = <XmlElement>{};
          fromXml.forEachResource((child) {
            final name = child.attributeName;
            if (keys.contains(name) &&
                !toResources
                    .any((c) => c is XmlElement && c.attributeName == name)) {
              final newNode = child.copy();
              toResources
                ..add(nlNode.copy())
                ..add(newNode);

              added.add(newNode);
            }
          });
          toResources.add(lastTextNode);

          if (added.isNotEmpty) {
            print('Added ${added.length} strings to ${toFile.path}');
            await toFile.writeAsString(toXml.toXmlString(
              // pretty: true,
              // indent: indent,
              //preserveWhitespace: (n) => !added.contains(n),
              entityMapping: _XmlEntityMapping(),
            ));
          }
        }
      }

      return success(message: 'All strings transferred.');
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

  String _getXmlPath(Directory baseDir, String subdirName) =>
      p.join(baseDir.path, subdirName, _fileName);

  File _getXmlFile(Directory baseDir, String subdirName) =>
      File(_getXmlPath(baseDir, subdirName));

  String _getXmlPathByLocale(Directory baseDir, String locale) =>
      _getXmlPath(baseDir, _getDirNameByLocale(locale));

  File _getXmlFileByLocale(Directory baseDir, String locale) =>
      File(_getXmlPathByLocale(baseDir, locale));

  String _getDirNameByLocale(String locale) =>
      locale.isNotEmpty ? '$_dirPrefix-$locale' : _dirPrefix;

  Future<List<String>> _getAllKeys(Directory fromDir, Directory toDir,
      Map<String, String> localesMap) async {
    final fromMap = await _loadValuesByKeys(_getXmlFileByLocale(fromDir, ''));
    final toMap = await _loadValuesByKeys(_getXmlFileByLocale(toDir, ''));
    return toMap.keys.where((key) {
      // TODO: check en translation (optional)
      return fromMap.containsKey(key);
    }).toList();
  }

  Future<Map<String, String>> _loadValuesByKeys(File file) async {
    final xml = await _loadXml(file);
    final data = <String, String>{};
    xml.forEachResource((child) {
      data[child.attributeName] = child.text;
    });

    return data;
  }
}

extension _XmlDocumentExtension on XmlDocument {
  XmlElement get resources => findAllElements('resources').first;

  void forEachResource(void Function(XmlElement child) callback) {
    for (final child in resources.children) {
      if (child is XmlElement) callback(child);
    }
  }
}

extension _XmlElementExtension on XmlElement {
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
