import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/models/models.dart';

// Payloads as the Unified Banking Platform's /api/v1/app returns them.
void main() {
  test('MoMo statuses map to the app states', () {
    expect(MomoRequest.fromJson({'id': 'a', 'status': 'PENDING'}).status, MomoStatus.pending);
    expect(MomoRequest.fromJson({'id': 'a', 'status': 'SUCCESSFUL'}).status, MomoStatus.successful);
    final f = MomoRequest.fromJson({
      'id': 'a',
      'status': 'FAILED',
      'message': 'Not completed. Your account was not debited.',
    });
    expect(f.status, MomoStatus.failed);
    expect(f.message, contains('not debited'));
  });

  test('cash-out quote from the platform', () {
    final q = CashoutQuote.fromJson({
      'quoteId': 'eyJ.sig',
      'amount': 20000,
      'fee': 144,
      'total': 20144,
      'expiresAt': '2026-11-24T18:05:00.000Z',
    });
    expect(q.fee, 144);
    expect(q.total, 20144);
  });

  test('loan and savings product shapes', () {
    final l = Loan.fromJson({
      'id': 'l1',
      'reference': 'LN-2026-000001',
      'principal': 120000,
      'outstanding': 100800,
      'status': 'active',
      'nextDueDate': '2026-12-24',
      'nextDueAmount': 21200,
    });
    expect(l.progress, closeTo(0.16, 0.001));
    final p = SavingsProduct.fromJson({
      'code': 'DAILY:M6',
      'name': 'Daily Saver · M6',
      'summary': '5% a year · 180 days',
      'subscribed': false,
      'balance': null,
    });
    expect(p.code, 'DAILY:M6');
    expect(p.subscribed, isFalse);
  });
}
