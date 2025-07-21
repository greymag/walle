class RunException implements Exception {
  final int code;
  final String? message;

  RunException(this.code, this.message);
  RunException.warn([this.message]) : code = 1;
  RunException.err([this.message]) : code = 2;

  @override
  String toString() {
    return 'RunException(code: $code, message: $message)';
  }
}
