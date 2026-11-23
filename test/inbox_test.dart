import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/cyclos/cyclos_inbox_api.dart';

void main() {
  test('notification', () {
    final n = InboxNotification.fromJson({
      'id': 'n1',
      'date': '2026-11-16T10:00:00Z',
      'subject': 'Payment request',
      'message': 'Jane requests 5 000 XAF',
      'read': false,
      'type': 'paymentRequestReceived',
      'entityType': 'transaction',
      'entityId': '-77',
    });
    expect(n.isPaymentRequest, isTrue);
    expect(n.entityId, '-77');
    expect(n.read, isFalse);
  });

  test('incoming payment request from /self/transactions', () {
    final r = IncomingPaymentRequest.fromJson({
      'id': '-77',
      'date': '2026-11-16T10:00:00Z',
      'amount': '-5000',
      'transactionNumber': 'PR-12',
      'description': 'School fees',
      'expirationDate': '2026-11-23T10:00:00Z',
      'related': {
        'user': {'display': 'Jane Doe'}
      },
    });
    expect(r.amount, 5000);
    expect(r.from, 'Jane Doe');
    expect(r.expires, isNotNull);
  });

  test('payment request preview', () {
    final p = PaymentRequestPreview.fromJson({
      'mainAmount': '5000',
      'totalAmount': '5039',
      'fees': [
        {'amount': '39'}
      ],
      'toAccount': {
        'user': {'display': 'Jane Doe'}
      },
      'confirmationPasswordInput': {'name': 'Transaction PIN', 'inputMethod': 'textBox'},
      'paymentRequest': {'transactionNumber': 'PR-12', 'description': 'School fees'},
    });
    expect(p.from, 'Jane Doe');
    expect(p.payment.totalAmount, 5039);
    expect(p.payment.requiresConfirmation, isTrue);
    expect(p.description, 'School fees');
  });
}
