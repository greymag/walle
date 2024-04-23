import 'package:walle/cli/commands/walle_command.dart';

abstract class BaseIapCommand extends WalleCommand {
  BaseIapCommand(String name, String description,
      {List<WalleCommand>? subcommands})
      : super(name, description, subcommands: subcommands);
}
