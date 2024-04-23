import 'package:walle/cli/commands/walle_command.dart';

import 'app_store/app_store_iap_command.dart';

/// Commands to work with IAPs.
class IapCommand extends WalleCommand {
  IapCommand()
      : super('iap', 'In-App Purchase', subcommands: [
          AppStoreIapCommand(),
        ]);

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}
