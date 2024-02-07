import 'dart:convert';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:walle/cli/exceptions/run_exception.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class GoogleSheetsApi {
  static final _clientId = utf8.decode(base64.decode(
      'MzI5OTExOTU5NS04ZXQ0ZW92MThvdm91Mm5iY2xzbzJrdnNwdWlra2gzcy5hcHBzLmdvb2dsZXVzZXJjb250ZW50LmNvbQ=='));
  static final _secret = utf8.decode(
      base64.decode('R09DU1BYLVRwRXAxYkVOcHRyM2ZWMzYwTEhyY0JCUHBINGw='));

  final void Function(String) prompt;
  final void Function(String)? log;
  SheetsApi? _api;

  GoogleSheetsApi(this.prompt, {this.log});

  Future<bool> connect() async {
    final client = await _obtainCredentials();
    _api = SheetsApi(client);
    return true;
  }

  Future<Spreadsheet> loadDocument(String url) async {
    final id = _getSpreadsheetIdFromUrl(url);
    return _api!.spreadsheets.get(id, includeGridData: true);
  }

  String _getSpreadsheetIdFromUrl(String url) {
    const preIdPart = '/spreadsheets/d/';
    final preIdPartIndex = url.indexOf(preIdPart);
    if (preIdPartIndex == -1) {
      throw RunException.err('Invalid Google Docs url.');
    }

    final startIdIndex = preIdPartIndex + preIdPart.length;
    final strStartWithId = url.substring(startIdIndex);
    final endIndex = strStartWithId.indexOf('/');
    return endIndex == -1
        ? strStartWithId
        : strStartWithId.substring(0, endIndex);
  }

  Future<AuthClient> _obtainCredentials() async {
    final clientId = ClientId(_clientId, _secret);
    final localData = await _loadLocalCredentials();

    if (localData == null) {
      log?.call('No saved credentials found. Start auth...');
      final client = await clientViaUserConsent(
        ClientId(_clientId, _secret),
        [SheetsApi.spreadsheetsScope],
        _prompt,
      );

      await _saveLocalCredentials(client.credentials);
      return client;
    } else {
      log?.call('Use saved credentials.');
      return autoRefreshingClient(
        clientId,
        localData,
        http.Client(),
      );
    }
  }

  Future<AccessCredentials?> _loadLocalCredentials() async {
    final file = await _getLocalCredentialsFile();
    log?.call('Check credential in ${file.path}');

    if (await file.exists()) {
      final json = await file.readAsString();
      return AccessCredentials.fromJson(
          jsonDecode(json) as Map<String, dynamic>);
    }

    return null;
  }

  Future<void> _saveLocalCredentials(AccessCredentials value) async {
    final json = jsonEncode(value.toJson());
    final file = await _getLocalCredentialsFile();
    await file.writeAsString(json);
    log?.call('Credentials saved to ${file.path}');
  }

  // Future<void> _removeLocalCredentials() async {
  //   final file = await _getLocalCredentialsFile();
  //   if (await file.exists()) {
  //     await file.delete();
  //   }
  // }

  // TODO: use another directory
  Future<File> _getLocalCredentialsFile() async => File(p.join(
      Directory.systemTemp.path, 'walle-google-sheets-credentials.json'));

  void _prompt(String url) {
    prompt('Please go to the following URL and grant access:');
    prompt('  => $url');
    prompt('');
  }
}
