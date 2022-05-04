import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/l10n/base_l10n_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

/// Command to transfer translations from one project to another.
class TransferL10nCommand extends BaseL10nCommand {
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
      final nlNode = XmlText('\n$indent');

      final fromDir = Directory(p.join(fromPath, subPath));
      final toDir = Directory(p.join(toPath, subPath));

      final keys = argKeys ??
          await _getAllKeys(fromDir, toDir, localesMap,
              validateByBase: locales != null);

      await for (final d in fromDir.list()) {
        final dirName = p.basename(d.path);
        if (dirName.startsWith(dirPrefix)) {
          final fromDirName = dirName;
          final fromFile = getXmlFile(fromDir, fromDirName);
          if (!fromFile.existsSync()) continue;

          final String toDirName;
          final String toLocale;

          final prefixEndIndex = dirName.indexOf('-');
          final locale = prefixEndIndex != -1
              ? dirName.substring(prefixEndIndex + 1)
              : baseLocale;

          if (localesMap.containsKey(locale)) {
            toLocale = localesMap[locale]!;
            toDirName = getDirNameByLocale(toLocale);
          } else {
            toLocale = locale;
            toDirName = dirName;
          }

          if (locales != null && !locales.contains(toLocale)) continue;

          final toFile = getXmlFile(toDir, toDirName);
          if (!toFile.existsSync()) continue;

          printVerbose('Processing $locale...');

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
            printInfo('Added ${added.length} strings to ${toFile.path}');
            await toFile.writeAsString(toXml.toXmlString(
              // pretty: true,
              // indent: indent,
              //preserveWhitespace: (n) => !added.contains(n),
              entityMapping: defaultXmlEntityMapping(),
            ));
          } else {
            printVerbose('Nothing');
          }
        }
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
    Map<String, String> localesMap, {
    bool validateByBase = false,
  }) async {
    final fromLocale = baseLocale;
    final toLocale =
        validateByBase ? (localesMap[fromLocale] ?? baseLocale) : baseLocale;
    final fromMap =
        await loadValuesByKeys(getXmlFileByLocale(fromDir, fromLocale));
    final toMap = await loadValuesByKeys(getXmlFileByLocale(toDir, toLocale));
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
