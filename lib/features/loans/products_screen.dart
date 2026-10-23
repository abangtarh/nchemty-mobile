import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/middleware/hub_api.dart';
import '../../data/models/models.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';

final loansProvider = FutureProvider.autoDispose<List<Loan>>(
    (ref) => ref.watch(hubApiProvider).loans());

final savingsProvider = FutureProvider.autoDispose<List<SavingsProduct>>(
    (ref) => ref.watch(hubApiProvider).savingsProducts());

/// Loans (LoanCoreLib) and ACAO DailySaver tiers, both via the middleware.
class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(ref);
    final loans = ref.watch(loansProvider);
    final savings = ref.watch(savingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('loansSavings'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(loansProvider);
          ref.invalidate(savingsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            loans.when(
              data: (list) => Column(
                children: [
                  for (final l in list.where((l) => l.outstanding > 0))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LoanCard(loan: l),
                    ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  ErrorRetry(error: e, onRetry: () => ref.invalidate(loansProvider)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.add),
              label: const Text('Apply for a new loan'),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Loan application form: phase 3')),
              ),
            ),
            const SizedBox(height: 24),
            const Text('ACAO Daily Saver',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            savings.when(
              data: (list) => Column(
                children: [
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        shape: p.subscribed
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: AppColors.gold, width: 2))
                            : null,
                        child: ListTile(
                          title: Text(p.name,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(p.subscribed && p.balance != null
                              ? 'Your plan · ${Money.xaf(p.balance)}'
                              : p.summary),
                          trailing: Text(p.subscribed ? 'View' : 'Open',
                              style: const TextStyle(
                                  color: AppColors.green, fontWeight: FontWeight.w700)),
                          onTap: p.subscribed
                              ? null
                              : () => _subscribe(context, ref, p),
                        ),
                      ),
                    ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  ErrorRetry(error: e, onRetry: () => ref.invalidate(savingsProvider)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribe(
      BuildContext context, WidgetRef ref, SavingsProduct p) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Open ${p.name}'),
        content: Text('${p.summary}\n\nBy continuing you accept the product terms.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('I accept')),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    final pin = await askConfirmationPassword(context);
    if (pin == null || pin.isEmpty || !context.mounted) return;
    try {
      await ref.read(hubApiProvider).subscribeSavings(
            productCode: p.code,
            initialDeposit: 0,
            acceptTerms: true,
            confirmationPassword: pin,
          );
      // WidgetRef of an unmounted ConsumerWidget throws on use.
      if (!context.mounted) return;
      ref.invalidate(savingsProvider);
      ref.invalidate(accountsProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _LoanCard extends ConsumerWidget {
  const _LoanCard({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = loan.nextDueDate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active loan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(loan.status, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${Money.xaf(loan.outstanding)} left',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: loan.progress,
                minHeight: 8,
                backgroundColor: AppColors.line,
                color: AppColors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                loan.reference,
                if (due != null && loan.nextDueAmount != null)
                  'Next: ${Money.xaf(loan.nextDueAmount)} on ${DateFormat('d MMM y').format(due)}',
              ].join(' · '),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () => _repay(context, ref),
              child: const Text('Repay now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _repay(BuildContext context, WidgetRef ref) async {
    final amount = (loan.nextDueAmount ?? loan.outstanding).round();
    final pin = await askConfirmationPassword(context,
        title: 'Repay ${Money.xaf(amount)}');
    if (pin == null || pin.isEmpty || !context.mounted) return;
    try {
      await ref.read(hubApiProvider).repayLoan(
            loanId: loan.id,
            amount: amount,
            confirmationPassword: pin,
            idempotencyKey: HubApi.newIdempotencyKey(),
          );
      if (!context.mounted) return;
      ref.invalidate(loansProvider);
      ref.invalidate(accountsProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
