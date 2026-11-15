import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/models/models.dart';
import 'package:nchemty_mobile/features/statements/statement_pdf.dart';

void main() {
  final account = AccountPeriodStatus.fromJson({
    'number': '0012345',
    'type': {'name': 'Current account'},
    'status': {
      'balanceAtBegin': '10000',
      'balanceAtEnd': '13500',
      'incoming': {'count': 1, 'sum': '5000'},
      'outgoing': {'count': 1, 'sum': '-1500'},
    },
  });

  HistoryEntry e(String amount, String date) => HistoryEntry.fromJson(
      {'id': date, 'amount': amount, 'date': date, 'transactionNumber': 'TX-$date'});

  test('period status reads Cyclos AccountWithHistoryStatus', () {
    expect(account.balanceAtBegin, 10000);
    expect(account.balanceAtEnd, 13500);
    expect(account.outgoingSum, 1500);
    expect(account.incomingCount, 1);
  });

  test('statement PDF builds', () async {
    final bytes = await buildStatementPdf(
      account: account,
      entries: [e('5000', '2026-11-02T09:00:00Z'), e('-1500', '2026-11-05T12:00:00Z')],
      from: DateTime(2026, 11),
      to: DateTime(2026, 11, 30),
      memberName: 'Test Member',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
