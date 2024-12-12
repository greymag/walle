import 'dart:io';

import 'package:app_store_server_sdk/app_store_server_sdk.dart';
import 'package:walle/cli/commands/iap/base_iap_command.dart';
import 'package:walle/cli/exceptions/run_exception.dart';

/// Work with AppStore IAP API
class AppStoreIapCommand extends BaseIapCommand {
  static const _argKeyName = 'keyName';
  static const _argKeyFilePath = 'keyFilePath';
  static const _argIssuerId = 'issuerId';
  static const _argAppBundle = 'appBundle';

  static const _argLookupOrder = 'lookupOrder';

  AppStoreIapCommand()
      : super(
          'appstore',
          'Work with AppStore IAP API.',
        ) {
    argParser
      ..addOption(
        _argKeyName,
        abbr: 'k',
        help: 'Key name (ID)',
        valueHelp: 'KEY_ID',
        mandatory: true,
      )
      ..addOption(
        _argKeyFilePath,
        abbr: 'p',
        help: 'Path to private key file (.p8)',
        valueHelp: 'PATH',
        mandatory: true,
      )
      ..addOption(
        _argIssuerId,
        abbr: 'i',
        help: 'Issuer ID',
        valueHelp: 'ISSUER_ID',
        mandatory: true,
      )
      ..addOption(
        _argAppBundle,
        abbr: 'a',
        help: 'Application bundle ID.',
        valueHelp: 'com.example.app',
        mandatory: true,
      )
      ..addOption(
        _argLookupOrder,
        abbr: 'l',
        help: 'Order ID from user for lookup. Action parameter',
        valueHelp: 'ABC123DE',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final keyName = args[_argKeyName] as String?;
    final keyPath = args[_argKeyFilePath] as String?;
    final issuerId = args[_argIssuerId] as String?;

    final appBundle = args[_argAppBundle] as String?;

    final lookupOrderId = args[_argLookupOrder] as String?;

    if (keyName == null ||
        keyPath == null ||
        issuerId == null ||
        appBundle == null) {
      return error(1, message: 'Missed required args');
    }

    if (lookupOrderId == null) {
      return error(1, message: 'You should provide one of action parameters.');
    }

    try {
      final appStoreEnvironment = AppStoreEnvironment.live(
        bundleId: appBundle,
        issuerId: issuerId,
        keyId: keyName,
        privateKey: File(keyPath).readAsStringSync(),
      );

      final appStoreHttpClient = AppStoreServerHttpClient(
        appStoreEnvironment,
        jwtTokenUpdatedCallback: (token) async {
          // TODO: Persist token for later re-use
        },
      );

      final api = AppStoreServerAPI(appStoreHttpClient);

      await _lookupOrder(api, lookupOrderId);

      return success(message: 'Done.');
    } on RunException catch (e) {
      return exception(e);
    } catch (e, st) {
      printVerbose('Exception: $e\n$st');
      return error(2, message: 'Failed by: $e');
    }
  }

  Future<void> _lookupOrder(AppStoreServerAPI api, String orderId) async {
    try {
      printInfo('Lookup for order: $orderId');
      final orderLookup = await api.lookUpOrderId(orderId);

      final transactions = orderLookup.signedTransactions;
      if (orderLookup.status == 0 &&
          transactions != null &&
          transactions.isNotEmpty) {
        printInfo(
            'Order lookup succeed! Transactions (${transactions.length}):');
        for (final jwtTransactions in transactions) {
          final decoded =
              JWSTransactionDecodedPayload.fromEncodedPayload(jwtTransactions);
          printInfo('- $decoded');
        }
      } else {
        printInfo('Order lookup failed: $orderLookup');
      }
    } on ApiException catch (e) {
      printError('Error: $e');
      throw RunException.err('Failed due API error');
    }
  }

  // Future<void> _subscriptionStatuses(AppStoreServerAPI api, String originalTransactionId) async {
  // final statusResponse =
  //     await api.getAllSubscriptionStatuses(originalTransactionId);
  // print(statusResponse);
  // print(
  //     'renewalInfo: ${statusResponse.data.first.lastTransactions.first.renewalInfo}');
  // print(
  //     'transactionInfo: ${statusResponse.data.first.lastTransactions.first.transactionInfo}');
  // }
}
