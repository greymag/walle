import 'package:args/command_runner.dart';
import 'package:walle/cli/commands/iap/iap_command.dart';
import 'package:walle/cli/commands/l10n/l10n_command.dart';
import 'package:walle/cli/commands/walle_command.dart';

class WalleCommandRunner extends CommandRunner<int> {
  WalleCommandRunner()
      : super('warren', 'A command tools for Android development.') {
    <WalleCommand>[
      L10nCommand(),
      IapCommand(),
    ].forEach(addCommand);
  }
}
