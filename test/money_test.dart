import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/core/utils/money.dart';

void main() {
  group('Money', () {
    test('formats XAF with space grouping', () {
      expect(Money.xaf(248500), '248 500 XAF');
      expect(Money.xaf('-150000.00'), '−150 000 XAF');
      expect(Money.xaf(20000, signed: true), '+20 000 XAF');
    });

    test('parses Cyclos decimal strings', () {
      expect(Money.parse('1500.00'), 1500);
      expect(Money.parse(null), 0);
    });

    test('reads amount input', () {
      expect(Money.fromInput('10 000'), 10000);
      expect(Money.fromInput(''), isNull);
    });
  });

}
