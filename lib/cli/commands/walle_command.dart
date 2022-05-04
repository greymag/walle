import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:walle/cli/out/out.dart' as out;
import 'package:meta/meta.dart';

/// Base class for a command implementation.
abstract class WalleCommand extends Command<int> {
  final String _name;
  final String _description;
  final ArgParser _argParser = ArgParser(
    allowTrailingOptions: false,
  )..addFlag('verbose', help: 'Show additional diagnostic info');

  WalleCommand(this._name, this._description,
      {List<WalleCommand>? subcommands}) {
    subcommands?.forEach(addSubcommand);
  }

  @override
  String get name => _name;

  @override
  ArgParser get argParser => _argParser;

  @override
  String get description => _description;

  bool get isVerbose => (argResults?['verbose'] ?? false) as bool;

  /// Prints message if verbose flag is on.
  @protected
  void printVerbose(String message) {
    if (isVerbose) out.verbose(message);
  }

  /// Prints some info message in output.
  @protected
  void printInfo(String message) => out.info(message);

  /// Prints error message in error output.
  @protected
  void printError(String message) => out.error(message);

  /// Prints 0 code and prints a success message if provided.
  @protected
  int success({String? message}) {
    if (message != null) printInfo(message);
    return 0;
  }

  /// Returns error code and prints a error message if provided.
  @protected
  int error(int code, {String? message}) {
    if (message != null) printError(message);
    return code;
  }

  /// Returns error code and prints a error message if provided.
  @protected
  int exception(RunException exception) {
    return error(exception.code, message: exception.message);
  }
}
