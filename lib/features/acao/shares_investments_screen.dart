import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/acao/acao_api.dart';
import '../auth/auth_controller.dart';
import '../common/widgets.dart';
import 'holdings_pdf.dart';

final acaoSharesProvider =
    FutureProvider.autoDispose<AcaoShareStatement>((ref) => ref.watch(acaoApiProvider).myShares());
final _shareClassesProvider =
    FutureProvider.autoDispose<List<AcaoShareClass>>((ref) => ref.watch(acaoApiProvider).shareClasses());
final acaoInvestmentsProvider =
    FutureProvider.autoDispose<List<AcaoInvestment>>((ref) => ref.watch(acaoApiProvider).myInvestments());
final _investmentProductsProvider = FutureProvider.autoDispose<List<AcaoInvestmentProduct>>(
    (ref) => ref.watch(acaoApiProvider).investmentProducts());

String _status(String s) => switch (s) {
      'requested' => 'Waiting for approval',
      'active' => 'Running',
      'matured' => 'Matured',
      'closed' => 'Closed',
      'rejected' => 'Refused',
      'cancelled' => 'Cancelled',
      'paid' => 'Paid',
      'queued' => 'Due',
      _ => s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}',
    };

Widget _badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );

Color _statusColor(String s) => switch (s) {
      'active' || 'executed' || 'paid' || 'matured' => AppColors.credit,
      'rejected' => AppColors.debit,
      _ => AppColors.muted,
    };

Future<void> _done(BuildContext context, String title, String body) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.credit, size: 40),
        title: Text(title),
        content: Text(body),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );

/// Shares (holdings, wallet, dividends, certificates, buy) and investments
/// (products, my investments, invest, close early), from Nchemty's hub.
class SharesInvestmentsScreen extends ConsumerWidget {
  const SharesInvestmentsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  Future<void> _statement(BuildContext context, WidgetRef ref) async {
    try {
      final api = ref.read(acaoApiProvider);
      AcaoShareStatement? shares;
      try {
        shares = await api.myShares();
      } on ApiException catch (_) {}
      final inv = await api.myInvestments().catchError((_) => <AcaoInvestment>[]);
      final bytes = await buildHoldingsPdf(
        memberName: ref.read(authProvider).user?.display ?? '',
        shares: shares,
        investments: inv,
      );
      await Printing.sharePdf(bytes: bytes, filename: 'nchemty-shares-investments.pdf');
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 2,
        initialIndex: initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Shares & investments'),
            actions: [
              IconButton(
                tooltip: 'Statement (PDF)',
                icon: const Icon(Icons.description_outlined),
                onPressed: () => _statement(context, ref),
              ),
            ],
            bottom: const TabBar(tabs: [Tab(text: 'Shares'), Tab(text: 'Investments')]),
          ),
          body: const TabBarView(children: [_SharesTab(), _InvestmentsTab()]),
        ),
      );
}

// ── Shares ────────────────────────────────────────────────────────────────

class _SharesTab extends ConsumerWidget {
  const _SharesTab();

  Future<void> _buy(BuildContext context, WidgetRef ref) async {
    List<AcaoShareClass> classes;
    try {
      classes = (await ref.read(_shareClassesProvider.future)).where((c) => c.active).toList();
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
      return;
    }
    if (!context.mounted) return;
    if (classes.isEmpty) {
      showApiError(context, ApiException('No shares are on offer at the moment.'));
      return;
    }
    final r = await showModalBottomSheet<(AcaoShareClass, int)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BuySheet(classes: classes),
    );
    if (r == null || !context.mounted) return;
    try {
      final ref_ = await ref.read(acaoApiProvider).buyShares(r.$1.code, r.$2);
      ref.invalidate(acaoSharesProvider);
      if (context.mounted) {
        await _done(context, 'Request sent',
            'Reference $ref_. Nothing is taken from your account until Nchemty approves it. Your certificate appears here once the shares are issued.');
      }
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _certificate(BuildContext context, WidgetRef ref, String no) async {
    try {
      final bytes = await ref.read(acaoApiProvider).shareCertificate(no);
      await Printing.sharePdf(bytes: bytes, filename: 'nchemty-share-certificate-$no.pdf');
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(acaoSharesProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(acaoSharesProvider);
        await ref.read(acaoSharesProvider.future);
      },
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: ErrorRetry(error: e, onRetry: () => ref.invalidate(acaoSharesProvider)),
          ),
        ]),
        data: (s) {
          final held = s.holdings.where((h) => h.units > 0).toList();
          final open = s.requests.where((r) => r.status == 'requested' || r.status == 'awaiting_buyer').toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: AppColors.green,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('My shares, value today', style: TextStyle(color: AppColors.gold)),
                    const SizedBox(height: 4),
                    Text(Money.xaf(s.totalValue),
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _buy(context, ref),
                icon: const Icon(Icons.add_chart),
                label: const Text('Buy shares'),
              ),
              const SizedBox(height: 16),
              if (held.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('You hold no shares yet.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              for (final h in held)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: Text(h.cls.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        Text('${h.units} share${h.units == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      SummaryRow('Value today', Money.xaf(h.value), strong: true),
                      SummaryRow('Price per share',
                          '${Money.xaf(h.cls.price)}${h.cls.priceMode == 'variable' ? ' (set by Nchemty)' : ''}'),
                      SummaryRow('Paid in', Money.xaf(h.paidIn)),
                      if (h.pendingOut > 0) SummaryRow('Offered for sale', '${h.pendingOut}'),
                    ]),
                  ),
                ),
              for (final w in s.wallet.entries)
                Card(
                  color: AppColors.goldLight,
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.greenDark),
                    title: Text('Share wallet: ${Money.xaf(w.value)}'),
                    subtitle: const Text('Money towards shares that does not make a whole share yet. '
                        'It becomes shares by itself as soon as it can.'),
                  ),
                ),
              if (open.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                for (final r in open)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r.kindLabel} ${r.units != null ? '${r.units} shares' : Money.xaf(r.amount ?? 0)}'),
                    subtitle: Text(r.reference),
                    trailing: _badge(r.statusLabel, AppColors.muted),
                  ),
              ],
              if (s.dividends.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Dividends', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                for (final d in s.dividends)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(children: [
                        SummaryRow('${d.classCode} · ${d.periodStart ?? ''} – ${d.periodEnd ?? ''}',
                            Money.xaf(d.net), strong: true),
                        SummaryRow('Gross / tax', '${Money.xaf(d.gross)} / ${Money.xaf(d.tax)}'),
                        SummaryRow('Reference', d.reference),
                      ]),
                    ),
                  ),
              ],
              if (s.movements.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                for (final m in s.movements)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${m.label}: ${m.units.abs()} ${m.classCode}'),
                    subtitle: Text('${m.date ?? ''} · ${Money.xaf(m.amount.abs())}'),
                    trailing: m.certificateNo == null
                        ? null
                        : TextButton.icon(
                            onPressed: () => _certificate(context, ref, m.certificateNo!),
                            icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                            label: const Text('Certificate'),
                          ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BuySheet extends StatefulWidget {
  const _BuySheet({required this.classes});
  final List<AcaoShareClass> classes;

  @override
  State<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends State<_BuySheet> {
  late AcaoShareClass _cls = widget.classes.first;
  final _units = TextEditingController(text: '1');

  @override
  void dispose() {
    _units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = int.tryParse(_units.text) ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Buy shares', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (widget.classes.length > 1)
            DropdownButtonFormField<AcaoShareClass>(
              initialValue: _cls,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Share class'),
              items: [
                for (final c in widget.classes)
                  DropdownMenuItem(value: c, child: Text('${c.name} · ${Money.xaf(c.price)}')),
              ],
              onChanged: (c) => setState(() => _cls = c ?? _cls),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _units,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Number of shares',
              helperText: [
                'A share costs ${Money.xaf(_cls.price)}',
                if (_cls.minUnits > 0) 'minimum ${_cls.minUnits} in total',
                if (_cls.maxUnits != null) 'maximum ${_cls.maxUnits} per member',
                if (_cls.available != null) '${_cls.available} available',
              ].join(' · '),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SummaryRow('Total', Money.xaf(units * _cls.price), strong: true),
          const SizedBox(height: 4),
          const Text('Paid from your account only once Nchemty approves the request.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: units >= 1 ? () => Navigator.pop(context, (_cls, units)) : null,
            child: const Text('Send request'),
          ),
        ],
      ),
    );
  }
}

// ── Investments ───────────────────────────────────────────────────────────

class _InvestmentsTab extends ConsumerWidget {
  const _InvestmentsTab();

  Future<void> _invest(BuildContext context, WidgetRef ref) async {
    List<AcaoInvestmentProduct> products;
    try {
      products = await ref.read(_investmentProductsProvider.future);
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
      return;
    }
    if (!context.mounted) return;
    if (products.isEmpty) {
      showApiError(context, ApiException('No investment is open at the moment.'));
      return;
    }
    final r = await showModalBottomSheet<(AcaoInvestmentProduct, num)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InvestSheet(products: products),
    );
    if (r == null || !context.mounted) return;
    try {
      final ref_ = await ref.read(acaoApiProvider).invest(r.$1.code, r.$2);
      ref.invalidate(acaoInvestmentsProvider);
      if (context.mounted) {
        await _done(context, 'Request sent',
            'Reference $ref_. An account officer reviews it; the amount is taken from your account and the term starts when it is approved.');
      }
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, AcaoInvestment i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text('${i.productName}: ${Money.xaf(i.amount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel request')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(acaoApiProvider).cancelInvestment(i.id);
      ref.invalidate(acaoInvestmentsProvider);
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _exit(BuildContext context, WidgetRef ref, AcaoInvestment i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close this investment early?'),
        content: const Text(
            'You get your capital back plus interest earned and not yet paid, less the early-closing penalty. '
            'The cooperative approves early closings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.debit),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Ask to close'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final q = await ref.read(acaoApiProvider).exitInvestment(i.id);
      ref.invalidate(acaoInvestmentsProvider);
      if (context.mounted) {
        await _done(context, 'Closing requested',
            'If approved you receive ${Money.xaf(q.total)}: capital ${Money.xaf(q.capital)} + interest ${Money.xaf(q.interest)} − penalty ${Money.xaf(q.forfeited)}.');
      }
    } on ApiException catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(acaoInvestmentsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(acaoInvestmentsProvider);
        await ref.read(acaoInvestmentsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _invest(context, ref),
            icon: const Icon(Icons.trending_up),
            label: const Text('Invest'),
          ),
          const SizedBox(height: 16),
          ...data.when<List<Widget>>(
            loading: () => [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
            error: (e, _) => [ErrorRetry(error: e, onRetry: () => ref.invalidate(acaoInvestmentsProvider))],
            data: (list) => list.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('You have no investments yet.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    ),
                  ]
                : [
                    for (final i in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [
                              Expanded(
                                child: Text(i.productName,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              ),
                              _badge(i.exitRequested ? 'Closing requested' : _status(i.status), _statusColor(i.status)),
                            ]),
                            SummaryRow('Amount', Money.xaf(i.amount), strong: true),
                            if (i.ratePa != null) SummaryRow('Rate', '${i.ratePa}% p.a.'),
                            if (i.termMonths != null) SummaryRow('Term', '${i.termMonths} months'),
                            if (i.startDate != null) SummaryRow('Started', i.startDate!),
                            if (i.maturityDate != null) SummaryRow('Matures', i.maturityDate!),
                            if (i.payments.isNotEmpty) SummaryRow('Interest paid so far', Money.xaf(i.interestPaid)),
                            SummaryRow('Reference', i.reference),
                            if (i.note?.isNotEmpty == true) SummaryRow('Note', i.note!),
                            if (i.payments.isNotEmpty)
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text('Payouts (${i.payments.length})'),
                                children: [
                                  for (final p in i.payments)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text('${p.kind == 'interest' ? 'Interest' : 'Capital'} · ${Money.xaf(p.amount)}'),
                                      subtitle: Text(p.dueOn ?? ''),
                                      trailing: _badge(_status(p.status), _statusColor(p.status)),
                                    ),
                                ],
                              ),
                            Wrap(alignment: WrapAlignment.end, children: [
                              if (i.status == 'requested')
                                TextButton(onPressed: () => _cancel(context, ref, i), child: const Text('Cancel request')),
                              if (i.status == 'active' && i.earlyExit && !i.exitRequested)
                                TextButton(onPressed: () => _exit(context, ref, i), child: const Text('Close early…')),
                            ]),
                          ]),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _InvestSheet extends StatefulWidget {
  const _InvestSheet({required this.products});
  final List<AcaoInvestmentProduct> products;

  @override
  State<_InvestSheet> createState() => _InvestSheetState();
}

class _InvestSheetState extends State<_InvestSheet> {
  late AcaoInvestmentProduct _p = widget.products.first;
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = num.tryParse(_amount.text) ?? 0;
    final valid = amount >= _p.minAmount && (_p.maxAmount == null || amount <= _p.maxAmount!);
    final interest = amount * _p.ratePa / 100 * _p.termMonths / 12;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Invest', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final p in widget.products)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: _p.code == p.code ? AppColors.green : Colors.transparent, width: 2),
                ),
                child: ListTile(
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    '${p.ratePa}% p.a. · ${p.termMonths} months',
                    if (p.payoutLabel.isNotEmpty) p.payoutLabel,
                    'from ${Money.xaf(p.minAmount)}${p.maxAmount == null ? '' : ' to ${Money.xaf(p.maxAmount!)}'}',
                    if (p.description?.isNotEmpty == true) p.description!,
                  ].join('\n')),
                  onTap: () => setState(() => _p = p),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Amount (XAF)',
                helperText: 'Minimum ${Money.xaf(_p.minAmount)}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (amount > 0)
              SummaryRow('Interest over the term (estimate)', Money.xaf(interest.round())),
            Text(
              _p.earlyExit
                  ? 'Can be closed early (penalty ${_p.penaltyPct}% of unpaid interest).'
                  : 'Cannot be closed before maturity.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: valid ? () => Navigator.pop(context, (_p, amount)) : null,
              child: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
