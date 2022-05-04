import 'package:args/command_runner.dart';
import 'package:walle/cli/out/out.dart' as out;
import 'package:walle/cli/runner.dart';

Future<int?> run(List<String> args) async {
  try {
    return await WalleCommandRunner().run(args);
  } on UsageException catch (e) {
    out.exception(e);
    return 64;
  } catch (e) {
    out.exception(e);
    return -1;
  }
}
