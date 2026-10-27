import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/cyclos/cyclos_qr_api.dart';
import 'package:nchemty_mobile/data/models/models.dart';

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

  test('ticket view reads status, approve link and paid transaction', () {
    final open = TicketInfo.fromJson({
      'ticketNumber': 'T1',
      'ticketStatus': 'open',
      'amount': '2500.00',
      'approveUrl': 'https://ebank.nchemty.com/pay/T1',
      'to': {'user': {'display': 'Shop'}},
    });
    expect(open.isOpen, isTrue);
    expect(open.isPaid, isFalse);
    expect(open.approveUrl, endsWith('/pay/T1'));
    expect(open.payeeName, 'Shop');

    final paid = TicketInfo.fromJson({
      'ticketNumber': 'T1',
      'ticketStatus': 'processed',
      'amount': '2500',
      'transaction': {'transactionNumber': 'TX-9'},
    });
    expect(paid.isPaid, isTrue);
    expect(paid.transactionNumber, 'TX-9');
  });

  test('payment type keeps destination account type for receiving', () {
    final t = PaymentType.fromJson({
      'id': '5',
      'name': 'QR payment',
      'from': {'id': '-1'},
      'to': {'id': '-9'},
    });
    expect(t.toId, '-9');
  });
}
