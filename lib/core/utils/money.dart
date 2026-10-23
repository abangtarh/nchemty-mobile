import 'package:intl/intl.dart';

/// XAF has no minor unit in practice; Cyclos may still send "1500.00".
class Money {
  Money._();

  static final _fmt = NumberFormat.decimalPattern('fr');

  /// Parses Cyclos decimal strings ("-150000.00") or numbers.
  static num parse(Object? value) {
    if (value == null) return 0;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? 0;
  }

  /// 248500 -> "248 500 XAF" (narrow no-break spaces normalised to spaces).
  static String xaf(Object? value, {bool signed = false}) {
    final n = parse(value).round();
    final body = _fmt.format(n.abs()).replaceAll(' ', ' ').replaceAll(' ', ' ');
    final sign = n < 0 ? '−' : (signed && n > 0 ? '+' : '');
    return '$sign$body XAF';
  }

  /// Digits only, for amount fields ("10 000" -> 10000).
  static int? fromInput(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.parse(digits);
  }
}
