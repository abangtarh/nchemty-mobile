import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/acao/acao_api.dart';
import '../common/widgets.dart';

final _productsProvider = FutureProvider.autoDispose<List<AcaoProduct>>(
    (ref) => ref.watch(acaoApiProvider).savingsProducts());

Future<void> _submitted(BuildContext context, String title, String message) async {
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.check_circle, color: AppColors.credit, size: 40),
      title: Text(title),
      content: Text(message),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
    ),
  );
  if (context.mounted) context.pop();
}

/// Open an ACAO savings account: product → term → goal → review → submit.
class SavingsApplyScreen extends ConsumerStatefulWidget {
  const SavingsApplyScreen({super.key});

  @override
  ConsumerState<SavingsApplyScreen> createState() => _SavingsApplyScreenState();
}

class _SavingsApplyScreenState extends ConsumerState<SavingsApplyScreen> {
  AcaoProduct? _product;
  AcaoTerm? _term;
  final _goal = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _product, t = _term;
    if (p == null || t == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit application?'),
        content: Text(p.applicationFee == null
            ? 'An application fee is charged now from your account.'
            : 'The application fee of ${Money.xaf(p.applicationFee!)} is charged now from your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final ref_ = await ref.read(acaoApiProvider).applySavings(
            productId: p.id,
            termCode: t.code,
            goal: _goal.text,
          );
      if (!mounted) return;
      await _submitted(
        context,
        'Application submitted',
        'Reference $ref_. An account officer will review it. On approval your term starts'
            '${p.setupFee == null ? '' : ' and the setup fee of ${Money.xaf(p.setupFee!)} is charged'}.',
      );
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(_productsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Open a savings account')),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: ErrorRetry(error: e, onRetry: () => ref.invalidate(_productsProvider))),
        data: (list) {
          final published = list.isNotEmpty && list.first.ratesPublished;
          final p = _product, t = _term;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (list.isNotEmpty && !published)
                Card(
                  color: AppColors.goldLight,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                        '${list.first.rateYear ?? 'This year\'s'} rates are not published yet, so new applications are closed for now.'),
                  ),
                ),
              const Text('1. Choose a product', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final prod in list)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: p?.id == prod.id ? AppColors.green : Colors.transparent, width: 2),
                  ),
                  child: ListTile(
                    title: Text(prod.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      if (prod.terms.isNotEmpty)
                        '${prod.terms.first.code}–${prod.terms.last.code}',
                      if (prod.ratesPublished && prod.terms.isNotEmpty)
                        '${prod.terms.first.ratePa ?? '?'}–${prod.terms.last.ratePa ?? '?'}% p.a.',
                      if (prod.depositCeiling != null) 'up to ${Money.xaf(prod.depositCeiling!)}',
                    ].join(' · ')),
                    trailing: Icon(p?.id == prod.id ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: AppColors.green),
                    onTap: () => setState(() {
                      _product = prod;
                      _term = prod.terms.isEmpty ? null : prod.terms.first;
                    }),
                  ),
                ),
              if (p != null) ...[
                const SizedBox(height: 16),
                const Text('2. Choose a term', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final term in p.terms)
                    ChoiceChip(
                      label: Text(
                          '${term.code} · ${term.days} days${term.ratePa == null ? '' : ' · ${term.ratePa}%'}'),
                      selected: t?.code == term.code,
                      onSelected: (_) => setState(() => _term = term),
                    ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _goal,
                  decoration: const InputDecoration(
                      labelText: 'Savings goal (optional)', hintText: 'e.g. School fees, land'),
                ),
              ],
              if (p != null && t != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Column(children: [
                      SummaryRow('Product', p.name),
                      SummaryRow('Term', '${t.code} — ${t.days} days'),
                      SummaryRow('Interest rate', t.ratePa == null ? 'Pending' : '${t.ratePa}% p.a.'),
                      if (p.depositCeiling != null) SummaryRow('Deposit ceiling', Money.xaf(p.depositCeiling!)),
                      SummaryRow('Application fee',
                          p.applicationFee == null ? '—' : '${Money.xaf(p.applicationFee!)} (now)'),
                      SummaryRow('Setup fee',
                          p.setupFee == null ? '—' : '${Money.xaf(p.setupFee!)} (if approved)'),
                      if (p.penaltyPct != null)
                        SummaryRow('Early withdrawal', '${p.penaltyPct}% of accrued interest'),
                      const SummaryRow('Start date', 'On approval'),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || !published ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit application'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Apply for a loan: amount, term, purpose. Nchemty sets the rate; the
/// application then goes through three approvals.
class LoanApplyScreen extends ConsumerStatefulWidget {
  const LoanApplyScreen({super.key});

  @override
  ConsumerState<LoanApplyScreen> createState() => _LoanApplyScreenState();
}

class _LoanApplyScreenState extends ConsumerState<LoanApplyScreen> {
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  int _months = 12;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  num? get _amountValue => num.tryParse(_amount.text.replaceAll(RegExp(r'[\s,]'), ''));

  Future<void> _submit() async {
    final amount = _amountValue;
    if (amount == null || amount <= 0 || _purpose.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(acaoApiProvider)
          .applyLoan(amount: amount, termMonths: _months, purpose: _purpose.text);
      if (!mounted) return;
      await _submitted(
        context,
        'Loan application submitted',
        'Reference $r. It is reviewed by the branch manager, the operations manager and the '
            'credit committee, in that order. You can follow each step under Loans.',
      );
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = (_amountValue ?? 0) > 0 && _purpose.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for a loan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Amount (XAF)', hintText: 'e.g. 450000'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _months,
            decoration: const InputDecoration(labelText: 'Repay over'),
            items: [
              for (final m in const [3, 6, 9, 12, 18, 24, 36])
                DropdownMenuItem(value: m, child: Text('$m months')),
            ],
            onChanged: (v) => setState(() => _months = v ?? _months),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _purpose,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Purpose', hintText: 'e.g. Shop stock'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          const Text(
            'The interest rate is set by Nchemty. Your application is reviewed by the branch '
            'manager, the operations manager and the credit committee before the loan is granted.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy || !valid ? null : _submit,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit application'),
          ),
        ],
      ),
    );
  }
}
