import 'package:walle/cli/commands/l10n/transfer/transfer_l10n_command.dart';
import 'package:walle/cli/commands/walle_command.dart';

/// Commands to work with localization.
class L10nCommand extends WalleCommand {
  L10nCommand()
      : super('l10n', 'Localization', subcommands: [
          TransferL10nCommand(),
        ]);

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}
