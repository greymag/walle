import 'package:list_ext/list_ext.dart';

part 'lang_codes.data.dart';

class LangCodes {
  /// A list of country data for every country
  static List<LangCode> getList() {
    return _kLangCodes;
  }

  /// Returns the `LangCode` for the given country alpha2 code.
  static LangCode? getByAlpha2(String alpha2) {
    final needle = alpha2.toLowerCase();
    return _kLangCodes.firstWhereOrNull((entry) => entry.alpha2 == needle);
  }

  /// Returns the `LangCode` for the given country alpha3 code.
  static LangCode? getByAlpha3(String alpha3) {
    final needle = alpha3.toLowerCase();
    return _kLangCodes.firstWhereOrNull((entry) => entry.alpha3 == needle);
  }

  LangCodes._();
}

class LangCode {
  final String name;
  final String alpha2;
  final String alpha3;

  const LangCode({
    required this.name,
    required this.alpha2,
    required this.alpha3,
  });
}
