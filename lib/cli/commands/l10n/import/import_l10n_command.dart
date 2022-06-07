import 'package:walle/cli/commands/walle_command.dart';

import 'googledoc_import_l10n_command.dart';

/// Commands to import localization.
class ImportL10nCommand extends WalleCommand {
  ImportL10nCommand()
      : super('import', 'Import localization', subcommands: [
          GoolgedocImportL10nCommand(),
        ]);

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}
