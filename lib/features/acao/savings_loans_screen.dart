import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/acao/acao_api.dart';
import '../common/widgets.dart';

final acaoAccountsProvider = FutureProvider.autoDispose<List<AcaoSavingsAccount>>(
    (ref) => ref.watch(acaoApiProvider).savingsAccounts());
final acaoApplicationsProvider = FutureProvider.autoDispose<List<AcaoLoanApplication>>(
    (ref) => ref.watch(acaoApiProvider).loanApplications());
final acaoLoansProvider =
    FutureProvider.autoDispose<List<AcaoLoan>>((ref) => ref.watch(acaoApiProvider).loans());

final _df = DateFormat('d MMM y');

String _statusLabel(String s) => switch (s) {
      'active' => 'Active',
      'matured' => 'Matured',
      'closed' => 'Closed',
      'pending' => 'Under review',
      'approved' => 'Approved',
      'granted' => 'Granted',
      'rejected' => 'Not approved',
      'withdrawn' => 'Withdrawn',
      'repaid' => 'Repaid',
      'delinquent' => 'Overdue',
      _ => s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}',
    };

Color _statusColor(String s) => switch (s) {
      'active' || 'granted' || 'approved' || 'repaid' => AppColors.credit,
      'rejected' || 'delinquent' => AppColors.debit,
      _ => AppColors.muted,
    };

Widget _chip(String status) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_statusLabel(status),
          style: TextStyle(color: _statusColor(status), fontSize: 12, fontWeight: FontWeight.w700)),
    );

/// Savings (ACAO) and loans from Nchemty's platform (acao.nchemty.com).
class SavingsLoansScreen extends StatelessWidget {
  const SavingsLoansScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Savings & loans'),
            bottom: const TabBar(tabs: [Tab(text: 'Savings'), Tab(text: 'Loans')]),
          ),
          body: const TabBarView(children: [_SavingsTab(), _LoansTab()]),
        ),
      );
}

// ── Savings ───────────────────────────────────────────────────────────────

class _SavingsTab extends ConsumerWidget {
  const _SavingsTab();

  Future<void> _withdraw(BuildContext context, WidgetRef ref, AcaoSavingsAccount a) async {
    final api = ref.read(acaoApiProvider);
    AcaoWithdrawalQuote q;
    try {
      q = await api.withdrawalQuote(a.id);
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
      return;
    }
    if (!context.mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Early withdrawal',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SummaryRow('Principal', Money.xaf(q.principal)),
            SummaryRow('Interest accrued', Money.xaf(q.accruedInterest)),
            SummaryRow('Penalty (${q.penaltyPct}% of interest)', '− ${Money.xaf(q.penalty)}'),
            SummaryRow('You receive', Money.xaf(q.totalPayout), strong: true),
            const SizedBox(height: 8),
            const Text('The account closes immediately and cannot be reopened.',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.debit),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm withdrawal'),
            ),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final paid = await api.withdrawEarly(a.id);
      ref.invalidate(acaoAccountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Withdrawal requested: ${Money.xaf(paid)} is being paid to your account.')));
      }
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(acaoAccountsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(acaoAccountsProvider);
        await ref.read(acaoAccountsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () async {
              await context.push('/acao/savings/apply');
              ref.invalidate(acaoAccountsProvider);
            },
            icon: const Icon(Icons.savings_outlined),
            label: const Text('Open a savings account'),
          ),
          const SizedBox(height: 16),
          ...accounts.when<List<Widget>>(
            loading: () => [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
            error: (e, _) => [ErrorRetry(error: e, onRetry: () => ref.invalidate(acaoAccountsProvider))],
            data: (list) => list.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('You have no savings accounts yet.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    ),
                  ]
                : [
                    for (final a in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text('${a.productName} · ${a.termCode}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                ),
                                _chip(a.status),
                              ]),
                              const SizedBox(height: 6),
                              SummaryRow('Contributed', Money.xaf(a.principal), strong: true),
                              SummaryRow(
                                  'Interest accrued',
                                  a.accruedThrough == null
                                      ? '${Money.xaf(a.accruedInterest)} (starts after day 1)'
                                      : '${Money.xaf(a.accruedInterest)} (to ${a.accruedThrough})'),
                              SummaryRow('Rate this year',
                                  a.currentRatePa == null ? 'Not yet published' : '${a.currentRatePa}% p.a.'),
                              if (a.termStart != null) SummaryRow('Started', _df.format(a.termStart!)),
                              if (a.maturity != null) SummaryRow('Matures', _df.format(a.maturity!)),
                              if (a.status == 'matured' && a.payoutPrincipal != null)
                                SummaryRow('Paid out',
                                    '${Money.xaf(a.payoutPrincipal!)} + ${Money.xaf(a.payoutInterest ?? 0)} interest'),
                              if (a.status == 'closed' && a.payoutPrincipal != null)
                                SummaryRow('Withdrawn early',
                                    '${Money.xaf((a.payoutPrincipal ?? 0) + (a.payoutInterest ?? 0))} (${Money.xaf(a.penaltyForfeited ?? 0)} forfeited)'),
                              if (a.isActive)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => _withdraw(context, ref, a),
                                    child: const Text('Withdraw early…'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

// ── Loans ─────────────────────────────────────────────────────────────────

class _LoansTab extends ConsumerWidget {
  const _LoansTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(acaoApplicationsProvider);
    final loans = ref.watch(acaoLoansProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(acaoApplicationsProvider);
        ref.invalidate(acaoLoansProvider);
        await ref.read(acaoLoansProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () async {
              await context.push('/acao/loans/apply');
              ref.invalidate(acaoApplicationsProvider);
            },
            icon: const Icon(Icons.request_page_outlined),
            label: const Text('Apply for a loan'),
          ),
          const SizedBox(height: 20),
          const Text('My loans', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...loans.when<List<Widget>>(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [ErrorRetry(error: e, onRetry: () => ref.invalidate(acaoLoansProvider))],
            data: (list) => list.isEmpty
                ? [const Text('No loans yet.', style: TextStyle(color: AppColors.muted))]
                : [
                    for (final l in list)
                      Card(
                        child: ListTile(
                          title: Text(Money.xaf(l.principal),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text([
                            l.reference,
                            if (l.ratePa != null) '${l.ratePa}% p.a.',
                            if (l.grantedAt != null) 'granted ${_df.format(l.grantedAt!)}',
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            _chip(l.status),
                            const Icon(Icons.chevron_right, color: AppColors.muted),
                          ]),
                          onTap: () => context.push('/acao/loans/${Uri.encodeComponent(l.id)}'),
                        ),
                      ),
                  ],
          ),
          const SizedBox(height: 20),
          const Text('Applications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...apps.when<List<Widget>>(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [ErrorRetry(error: e, onRetry: () => ref.invalidate(acaoApplicationsProvider))],
            data: (list) {
              final open = list.where((a) => a.status != 'granted').toList();
              return open.isEmpty
                  ? [const Text('No applications in progress.', style: TextStyle(color: AppColors.muted))]
                  : [for (final a in open) _ApplicationCard(app: a)];
            },
          ),
        ],
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app});
  final AcaoLoanApplication app;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(Money.xaf(app.amount),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                _chip(app.status),
              ]),
              const SizedBox(height: 4),
              Text([
                app.reference,
                if (app.termMonths != null) '${app.termMonths} months',
                if (app.purpose?.isNotEmpty == true) app.purpose!,
              ].join(' · '), style: const TextStyle(color: AppColors.muted)),
              if (app.authorizations.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final a in app.authorizations)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Icon(
                        a.decision == 'approved'
                            ? Icons.check_circle
                            : a.decision == 'rejected'
                                ? Icons.cancel
                                : Icons.radio_button_unchecked,
                        size: 18,
                        color: a.decision == 'approved'
                            ? AppColors.credit
                            : a.decision == 'rejected'
                                ? AppColors.debit
                                : AppColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.levelLabel)),
                      Text(a.decision == null ? 'Pending' : _statusLabel(a.decision!),
                          style: const TextStyle(color: AppColors.muted)),
                    ]),
                  ),
              ],
            ],
          ),
        ),
      );
}

/// Repayment schedule of one loan.
class AcaoLoanDetailScreen extends ConsumerWidget {
  const AcaoLoanDetailScreen({super.key, required this.loanId});
  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loan = ref.watch(_loanProvider(loanId));
    return Scaffold(
      appBar: AppBar(title: const Text('Loan')),
      body: loan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: ErrorRetry(error: e, onRetry: () => ref.invalidate(_loanProvider(loanId)))),
        data: (l) {
          final remaining = l.schedule.where((s) => s.status != 'paid').fold<num>(0, (t, s) => t + s.total);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(children: [
                    SummaryRow('Reference', l.reference),
                    SummaryRow('Amount', Money.xaf(l.principal), strong: true),
                    if (l.ratePa != null) SummaryRow('Rate', '${l.ratePa}% p.a.'),
                    if (l.grantedAt != null) SummaryRow('Granted', _df.format(l.grantedAt!)),
                    SummaryRow('Status', _statusLabel(l.status)),
                    if (l.schedule.isNotEmpty) SummaryRow('Still to pay', Money.xaf(remaining), strong: true),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Repayment schedule', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final s in l.schedule)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.goldLight,
                      foregroundColor: AppColors.greenDark,
                      child: Text('${s.no}'),
                    ),
                    title: Text(Money.xaf(s.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${s.dueDate == null ? '' : 'Due ${_df.format(s.dueDate!)} · '}${Money.xaf(s.principalDue)} + ${Money.xaf(s.interestDue)} interest'),
                    trailing: _chip(s.status),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

final _loanProvider =
    FutureProvider.autoDispose.family<AcaoLoan, String>((ref, id) => ref.watch(acaoApiProvider).loan(id));
