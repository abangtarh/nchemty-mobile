import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/core/network/api_exception.dart';
import 'package:nchemty_mobile/data/models/models.dart';

// Shapes follow the Nchemty Cyclos 4.16.17 openapi.json.
void main() {
  test('payment type uses the qualified internal name', () {
    final t = PaymentType.fromJson({
      'id': '-123',
      'name': 'Member payment',
      'internalName': 'memberPayment',
      'from': {'id': '-9', 'internalName': 'memberAccount'},
    });
    expect(t.id, 'memberAccount.memberPayment');
    expect(t.name, 'Member payment');
  });

  test('payment type falls back to id without internal names', () {
    final t = PaymentType.fromJson({'id': '-123', 'name': 'Pay'});
    expect(t.id, '-123');
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
}
