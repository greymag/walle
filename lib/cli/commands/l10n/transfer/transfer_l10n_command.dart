import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:walle/cli/commands/walle_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:xml/xml.dart';

/// Command to export summary data from all account.
class TransferL10nCommand extends WalleCommand {
  static const _argFrom = 'from';
  static const _argTo = 'to';
  // TODO: list of keys?

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
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final fromPath = args[_argFrom] as String?;
    final toPath = args[_argTo] as String?;

    const keys = [
      // 'permission_grant_error',
      // 'statistics_permission_name',
      // 'overlay_permission_name',
      // 'picture_in_picture_permission_name',
      // 'start_activity_from_background_permission_name',
      // 'accessibility_permission_name',
      // 'manage_storage_permission_name',
      // 'start_activity_from_background_permission_reason',
      // 'cooler_statistics_permission_reason',
      // 'pip_or_overlay_permission_reason',
      // 'permission_required',
      // 'cache_statistics_permission_reason',
      // 'write_external_storage_permission_name',
      // 'android_data_storage_permission_name',
      // 'text_storage_additional_description',
      // 'order_number_of',
      // 'storage_for_clear_permission_reason',
      // 'text_get_permissions_folder_android_data_for_clean_dialog_message',
      // 'notification_manager_permission_name',
      // 'force_stop_statistics_permission_reason',
      // 'android_data_permission_reason',
      // 'storage_for_file_manager_permission_reason',
      // 'optimization_battery_statistics_permission_reason',
      'text_scan_in_process',
    ];

    const localesMap = {
      '': 'en',
      'zh-rCN': '',
    };

    if (fromPath == null || toPath == null) {
      return error(1, message: 'Both paths are required.');
    }

    try {
      // src/main/res/values-ar/strings.xml
      const subPath = 'src/main/res/';
      const fileName = 'strings.xml';
      const dirPrefix = 'values';
      const indent = '    ';
      final nlNode = XmlText('\n$indent');

      final fromDir = Directory(p.join(fromPath, subPath));
      final toDir = Directory(p.join(toPath, subPath));

      await for (final d in fromDir.list()) {
        final dirName = p.basename(d.path);
        if (dirName.startsWith(dirPrefix)) {
          final fromDirName = dirName;
          final String toDirName;

          final prefixEndIndex = dirName.indexOf('-');
          final locale =
              prefixEndIndex != -1 ? dirName.substring(prefixEndIndex + 1) : '';

          if (localesMap.containsKey(locale)) {
            final toLocale = localesMap[locale]!;
            if (toLocale.isNotEmpty) {
              toDirName = '$dirPrefix-$toLocale';
            } else {
              toDirName = dirPrefix;
            }
          } else {
            toDirName = dirName;
          }

          final fromFile = File(p.join(fromDir.path, fromDirName, fileName));
          final toFile = File(p.join(toDir.path, toDirName, fileName));

          // if (fromDirName != toDirName) print('From $fromFile to $toFile');

          if (!fromFile.existsSync() || !toFile.existsSync()) continue;

          final fromXml = await _loadXml(fromFile);
          final toXml = await _loadXml(toFile);

          final fromResources = fromXml.resources;
          final toResources = toXml.resources;

          final lastTextNode = toResources.children.removeLast();

          final added = <XmlElement>{};
          for (final child in fromResources.children) {
            if (child is XmlElement) {
              final name = child.attributeName;
              if (keys.contains(name) &&
                  !toResources.children
                      .any((c) => c is XmlElement && c.attributeName == name)) {
                final newNode = child.copy();
                toResources.children
                  ..add(nlNode.copy())
                  ..add(newNode);

                added.add(newNode);
              }
            }
          }
          toResources.children.add(lastTextNode);

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
}

extension _XmlDocumentExtension on XmlDocument {
  XmlElement get resources => findAllElements('resources').first;
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
