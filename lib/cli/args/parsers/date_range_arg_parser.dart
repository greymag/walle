import 'package:args/args.dart';
import 'package:in_date_range/in_date_range.dart';
import 'package:in_date_utils/in_date_utils.dart';

class DateRangeArgParser {
  static const helpExamples = 'You can:\n'
      '- specify 2 dates (inclusively), e.g. -r2021/06/13-2021/06/15;\n'
      '- specify numbers of previous days, '
      'e.g. -r-7d exports 7 previous days, today excluded (-r-0d means today);\n';

  const DateRangeArgParser();

  DateRange? parse(ArgResults? argResults, String argName) {
    final input = argResults?[argName] as String?;
    if (input == null) return null;

    DateTime? start;
    DateTime? end;

    if (input.startsWith('-')) {
      // -{days}d
      if (input.endsWith('d')) {
        final days = int.tryParse(input.substring(1, input.length - 1));
        if (days != null && days >= 0) {
          end = days > 0 ? DTU.startOfToday() : DateTime.now();
          start = DateTime(end.year, end.month, end.day - days);
        }
      }
    } else {
      final parts = input.split('-');
      if (parts.length != 2) return null;

      start = _parseDate(parts[0]);
      end = _parseDate(parts[1]);

      if (end != null) end = DTU.nextDay(end);
    }

    if (start == null || end == null || !start.isBefore(end)) return null;

    return DateRange(start, end);
  }

  DateTime? _parseDate(String raw) {
    final parts = raw.split('/');
    if (parts.length != 3) return null;
    if (parts[0].length != 4) return null;
    final year = int.tryParse(parts[0]);
    if (year == null) return null;
    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return null;
    final day = int.tryParse(parts[2]);
    if (day == null || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }
}

extension DateRangeArgParserArgResultsExtension on ArgResults? {
  DateRange? dateRange(String name) =>
      const DateRangeArgParser().parse(this, name);
}
