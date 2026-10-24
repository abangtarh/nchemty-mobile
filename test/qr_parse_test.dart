import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/cyclos/cyclos_qr_api.dart';

// Assumes the default CYCLOS_URL (https://ebank.nchemty.com/api).
void main() {
  test('reads a real Nchemty /pay link', () {
    final qr = ScannedQr.parse(
        'https://ebank.nchemty.com/pay/vb1n1OVk5cf6JDdYfhtUvpYbztZadmTn');
    expect(qr, isA<PayLinkQr>());
    expect((qr as PayLinkQr).code, 'vb1n1OVk5cf6JDdYfhtUvpYbztZadmTn');
    expect(qr.amount, isNull);
  });

  test('keeps an amount from the query', () {
    final qr = ScannedQr.parse('https://ebank.nchemty.com/pay/abc?amount=3500');
    expect((qr as PayLinkQr).amount, 3500);
  });

  test('rejects other domains and plain http', () {
    expect(ScannedQr.parse('https://ebank-nchemty.com/pay/abc'), isNull);
    expect(ScannedQr.parse('http://ebank.nchemty.com/pay/abc'), isNull);
    expect(ScannedQr.parse(''), isNull);
  });

  test('plain text is treated as a member identifier', () {
    final qr = ScannedQr.parse(' jdoe ');
    expect(qr, isA<PrincipalQr>());
    expect((qr as PrincipalQr).value, 'jdoe');
  });
}
