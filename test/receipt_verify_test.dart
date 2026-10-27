import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/core/config/env.dart';
import 'package:nchemty_mobile/data/cyclos/cyclos_qr_api.dart';
import 'package:nchemty_mobile/data/cyclos/receipt_verify_api.dart';
import 'package:nchemty_mobile/data/models/models.dart';
import 'package:nchemty_mobile/features/receipts/receipt_pdf.dart';

// Assumes the default CYCLOS_URL (https://ebank.nchemty.com/api).
void main() {
  test('verify URL defaults to the Cyclos host /run/verify-receipt', () {
    expect(Env.receiptVerifyUrl, 'https://ebank.nchemty.com/run/verify-receipt');
  });

  test('receipt QR carries reference and amount', () {
    final t = TransferDetails.fromJson({
      'id': '1',
      'date': '2026-10-24T10:00:00Z',
      'amount': '-5000',
      'transactionNumber': 'TX-1',
    });
    expect(receiptQrData(t),
        'https://ebank.nchemty.com/run/verify-receipt?tx=TX-1&a=5000');
  });

  test('scanner recognises a receipt QR and never treats it as a payment', () {
    final qr = ScannedQr.parse(
        'https://ebank.nchemty.com/run/verify-receipt?tx=TX-1&a=5000');
    expect(qr, isA<ReceiptQr>());
    expect((qr as ReceiptQr).reference, 'TX-1');
    expect(qr.amount, 5000);
  });

  test('older slips (NCHEMTY|ref|amount|date) are still recognised', () {
    final qr = ScannedQr.parse('NCHEMTY|TX-7|2500 XAF|2026-10-24T10:00:00.000Z');
    expect(qr, isA<ReceiptQr>());
    expect((qr as ReceiptQr).reference, 'TX-7');
    expect(qr.amount, 2500);
  });

  test('json endpoint and answer', () {
    expect(
        ReceiptVerifyApi.jsonUri('https://ebank.nchemty.com/run/verify-receipt', 'TX-1', -5000)
            .toString(),
        'https://ebank.nchemty.com/run/verify-receipt/json?tx=TX-1&a=5000');
    final r = ReceiptVerification.fromJson(
        {'valid': true, 'reference': 'TX-1', 'amount': 5000, 'from': 'Abang T.'});
    expect(r.valid, isTrue);
    expect(r.amount, 5000);
    expect(ReceiptVerification.fromJson({'valid': false, 'reference': 'X'}).valid, isFalse);
  });
}
