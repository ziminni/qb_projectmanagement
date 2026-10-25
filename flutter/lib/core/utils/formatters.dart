import 'package:intl/intl.dart';

abstract final class Formatters {
  static final _peso = NumberFormat.currency(
    locale: 'en',
    symbol: '₱',
    decimalDigits: 2,
  );
  static final _pesoWhole = NumberFormat.currency(
    locale: 'en',
    symbol: '₱',
    decimalDigits: 0,
  );
  static final _date = DateFormat('MMM d, yyyy');
  static final _shortDate = DateFormat('MMM d');
  static final _dateTime = DateFormat('MMM d, yyyy h:mm a');

  static String peso(num amount) => _peso.format(amount);

  static String pesoWhole(num amount) => _pesoWhole.format(amount);

  /// Formats a 0–1 fraction as a whole percentage, e.g. 0.37 → "37%".
  static String percent(double fraction) => '${(fraction * 100).round()}%';

  static String date(DateTime value) => _date.format(value);

  static String shortDate(DateTime value) => _shortDate.format(value);

  static String dateTime(DateTime value) => _dateTime.format(value);

  static String dateRange(DateTime start, DateTime end) =>
      '${shortDate(start)} – ${date(end)}';
}
