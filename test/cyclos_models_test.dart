import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/core/network/api_exception.dart';
import 'package:nchemty_mobile/data/cyclos/cyclos_api.dart';
import 'package:nchemty_mobile/data/models/models.dart';

// Shapes follow the Nchemty Cyclos 4.16.17 openapi.json.
void main() {
  test('payment type keeps id and from-account type id', () {
    final t = PaymentType.fromJson({
      'id': '-123',
      'name': 'Member payment',
      'internalName': 'memberPayment',
      'from': {'id': '-9', 'internalName': 'memberAccount'},
    });
    expect(t.id, '-123');
    expect(t.fromId, '-9');
    expect(t.name, 'Member payment');
  });

  test('numeric identifiers are escaped like the official frontend', () {
    expect(CyclosApi.escapeNumeric('677123456'), "'677123456");
    expect(CyclosApi.escapeNumeric('jdoe'), 'jdoe');
  });

  test('timing builds Cyclos scheduling fields', () {
    expect(PayScheduled(DateTime(2026, 11, 5)).toJson(), {
      'scheduling': 'scheduled',
      'installmentsCount': 1,
      'firstInstallmentDate': '2026-11-05',
    });
    expect(
        PayRecurring(firstDate: DateTime(2026, 11, 1), every: 2, unit: 'weeks').toJson(), {
      'scheduling': 'recurring',
      'firstOccurrenceDate': '2026-11-01',
      'occurrenceInterval': {'amount': 2, 'field': 'weeks'},
    });
  });

  test('data-for-perform lists the accounts to pay from', () {
    final d = PaymentData.fromJson({
      'accounts': [
        {
          'id': 'a1',
          'type': {'id': '-9', 'internalName': 'memberAccount', 'name': 'Current'},
          'status': {'balance': '5000', 'availableBalance': '4000'},
        }
      ],
    });
    expect(d.accounts.single.typeKey, '-9');
    expect(d.accounts.single.available, 4000);
  });

  test('data-for-perform gives payee and types', () {
    final d = PaymentData.fromJson({
      'toUser': {'id': '7', 'display': 'Jane Doe'},
      'paymentTypes': [
        {'id': '1', 'name': 'A'},
        {'id': '2', 'name': 'B'},
      ],
    });
    expect(d.payee?.display, 'Jane Doe');
    expect(d.paymentTypes.length, 2);
  });

  test('preview reads fees, total and confirmation input', () {
    final p = PaymentPreview.fromJson({
      'mainAmount': '1000.00',
      'totalAmount': '1050.00',
      'fees': [
        {'amount': '50.00'}
      ],
      'toAccount': {
        'user': {'display': 'Jane Doe'}
      },
      'confirmationPasswordInput': {
        'allowedCredentials': ['password'],
        'passwordType': {'name': 'Transaction PIN', 'mode': 'manual', 'onlyNumeric': true},
      },
    });
    expect(p.amount, 1000);
    expect(p.fees, 50);
    expect(p.totalAmount, 1050);
    expect(p.recipient, 'Jane Doe');
    expect(p.requiresConfirmation, isTrue);
    expect(p.confirmation!.label, 'Transaction PIN');
    expect(p.confirmation!.usable, isTrue);
    expect(p.confirmation!.isOtp, isFalse);
  });

  test('no confirmation input means none required', () {
    final p = PaymentPreview.fromJson({'mainAmount': '10', 'totalAmount': '10'});
    expect(p.requiresConfirmation, isFalse);
  });

  test('device-only confirmation is flagged as not usable', () {
    final c = ConfirmationInput.fromJson({
      'allowedCredentials': ['device'],
    });
    expect(c!.usable, isFalse);
  });

  test('Cyclos payment error becomes a readable message with details', () {
    final req = RequestOptions(path: '/self/payments', method: 'POST');
    final e = ApiException.fromDio(DioException(
      requestOptions: req,
      response: Response(
        requestOptions: req,
        statusCode: 422,
        data: {'kind': 'payment', 'code': 'insufficientBalance'},
      ),
    ));
    expect(e.code, 'insufficientBalance');
    expect(e.message, contains('Not enough balance'));
    expect(e.details, contains('POST /self/payments'));
  });

  test('wrong confirmation PIN is recognised', () {
    final req = RequestOptions(path: '/self/payments', method: 'POST');
    final e = ApiException.fromDio(DioException(
      requestOptions: req,
      response: Response(
          requestOptions: req, statusCode: 403, data: {'code': 'invalidPassword'}),
    ));
    expect(e.isWrongConfirmation, isTrue);
  });

  test('history entry key escapes numeric transaction numbers', () {
    HistoryEntry e(String? n) => HistoryEntry.fromJson({
          'id': 'abc',
          'amount': '10',
          'date': '2026-10-24T10:00:00Z',
          if (n != null) 'transactionNumber': n,
        });
    expect(e('12345').key, "'12345");
    expect(e('TX-9').key, 'TX-9');
    expect(e(null).key, 'abc');
  });

  test('transfer details read parties, fees and statuses', () {
    final t = TransferDetails.fromJson({
      'id': '1',
      'date': '2026-10-24T10:00:00Z',
      'amount': '-5000',
      'transactionNumber': 'TX-1',
      'from': {'user': {'display': 'Abang'}, 'type': {'name': 'Current'}},
      'to': {'type': {'name': 'MoMo Transactions'}},
      'type': {'name': 'Cash out'},
      'children': [
        {'amount': '39', 'type': {'name': 'Cash-out fee'}}
      ],
      'statuses': {'flow1': {'name': 'Completed'}},
    });
    expect(t.fromName, 'Abang');
    expect(t.toName, 'MoMo Transactions');
    expect(t.fees.single.$2, 39);
    expect(t.statuses, ['Completed']);
  });
}
