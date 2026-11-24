import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/acao/acao_api.dart';

// Shapes returned by acao.nchemty.com (coop-platform src/api/router.js).
void main() {
  test('savings product with terms and fees', () {
    final p = AcaoProduct.fromJson({
      'id': 'ACAO_PRIME',
      'name': 'ACAO Prime',
      'deposit_ceiling': '5000000.00',
      'penalty_pct_of_interest': '25',
      'rate_year': 2026,
      'rates_published': true,
      'application_fee': 500,
      'setup_fee': '2000',
      'terms': [
        {'term_code': 'M12', 'days': 365, 'interest_rate_pa': '6.5'},
        {'term_code': 'M60', 'days': 1825, 'interest_rate_pa': 9},
      ],
    });
    expect(p.terms.map((t) => t.code), ['M12', 'M60']);
    expect(p.terms.first.ratePa, 6.5);
    expect(p.depositCeiling, 5000000);
    expect(p.setupFee, 2000);
    expect(p.ratesPublished, isTrue);
  });

  test('savings account', () {
    final a = AcaoSavingsAccount.fromJson({
      'id': 'a1',
      'product_name': 'ACAO DailySaver',
      'term_code': 'M12',
      'status': 'active',
      'principal': 12000,
      'accrued_interest': 37.5,
      'accrued_through': '2026-11-17',
      'term_start_date': '2026-01-10T00:00:00.000Z',
      'maturity_date': '2027-01-10T00:00:00.000Z',
      'current_rate_pa': '6.5',
    });
    expect(a.isActive, isTrue);
    expect(a.accruedInterest, 37.5);
    expect(a.maturity, isNotNull);
  });

  test('loan application with approval chain, and loan with schedule', () {
    final app = AcaoLoanApplication.fromJson({
      'id': 'x',
      'reference': 'APP-LN-1',
      'requested_amount': '450000.00',
      'term_months': 12,
      'purpose': 'Shop stock',
      'status': 'pending',
      'authorizations': [
        {'level': 'branch_manager', 'decision': 'approved'},
        {'level': 'operations_manager', 'decision': null},
      ],
    });
    expect(app.amount, 450000);
    expect(app.authorizations.first.levelLabel, 'Branch manager');
    expect(app.authorizations.last.decision, isNull);

    final loan = AcaoLoan.fromJson({
      'id': 'l1',
      'reference': 'LN-1',
      'principal': '450000',
      'interest_rate_pa': '9.5',
      'status': 'active',
      'schedule': [
        {'installment_no': 1, 'due_date': '2026-12-17', 'principal_due': '37500', 'interest_due': '3562.5', 'status': 'due'},
      ],
    });
    expect(loan.schedule.single.total, 41062.5);
  });

  test('early withdrawal quote', () {
    final q = AcaoWithdrawalQuote.fromJson({
      'savingsAccountId': 'a1',
      'principal': 12000,
      'accruedInterest': 40,
      'penaltyPct': 25,
      'penalty': 10,
      'totalPayout': 12030,
    });
    expect(q.totalPayout, 12030);
  });

  test('share statement from /shares/me', () {
    final s = AcaoShareStatement.fromJson({
      'wallet': [
        {'classCode': 'ORD', 'name': 'Ordinary', 'balance': 1500, 'price': 5000}
      ],
      'holdings': [
        {
          'code': 'ORD', 'name': 'Ordinary shares', 'kind': 'membership', 'nominalValue': 5000,
          'priceMode': 'fixed', 'minUnits': 1, 'maxUnits': 100, 'active': true, 'price': 5000,
          'available': null, 'units': 4, 'value': 20000, 'paidIn': 20000, 'pendingOut': 0,
        }
      ],
      'movements': [
        {'classCode': 'ORD', 'kind': 'subscribe', 'units': 4, 'unitPrice': 5000, 'amount': 20000,
         'certificateNo': 'SC-2026-000012', 'date': '2026-11-02'}
      ],
      'requests': [
        {'reference': 'SHR-SUB-1', 'kind': 'subscribe', 'status': 'requested', 'classCode': 'ORD', 'units': 2, 'mine': true},
        {'reference': 'SHR-TR-9', 'kind': 'transfer', 'status': 'awaiting_buyer', 'classCode': 'ORD', 'units': 1, 'mine': false},
      ],
      'dividends': [
        {'reference': 'DIV-2025', 'classCode': 'ORD', 'periodStart': '2025-01-01', 'periodEnd': '2025-12-31',
         'gross': 1200, 'tax': 180, 'net': 1020, 'status': 'approved'}
      ],
    });
    expect(s.totalValue, 20000);
    expect(s.holdings.single.cls.price, 5000);
    expect(s.wallet['ORD'], 1500);
    expect(s.movements.single.certificateNo, 'SC-2026-000012');
    expect(s.requests.single.statusLabel, 'Waiting for approval'); // only my own
    expect(s.dividends.single.net, 1020);
  });

  test('investment with payouts', () {
    final i = AcaoInvestment.fromJson({
      'id': '7', 'reference': 'INV-1', 'productCode': 'TB12', 'productName': 'Treasury 12m',
      'amount': 500000, 'ratePa': 8, 'termMonths': 12, 'status': 'active', 'earlyExit': true,
      'startDate': '2026-01-01', 'maturityDate': '2027-01-01',
      'payments': [
        {'kind': 'interest', 'dueOn': '2026-04-01', 'amount': 10000, 'status': 'paid'},
        {'kind': 'interest', 'dueOn': '2026-07-01', 'amount': 10000, 'status': 'queued'},
      ],
    });
    expect(i.interestPaid, 10000);
    expect(i.earlyExit, isTrue);
    final p = AcaoInvestmentProduct.fromJson(
        {'code': 'TB12', 'name': 'Treasury 12m', 'termMonths': 12, 'ratePa': 8, 'minAmount': 100000, 'payout': 'quarterly'});
    expect(p.payoutLabel, 'Interest paid quarterly');
  });
}
