import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';
import '../auth/auth_controller.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';
import 'statement_pdf.dart';

enum _Period { thisMonth, lastMonth, last3Months, thisYear, custom }

/// Account statement for a chosen account and period: Nchemty PDF (share or
/// print) built from Cyclos history, plus Cyclos's own export when offered.
class StatementScreen extends ConsumerStatefulWidget {
  const StatementScreen({super.key, this.accountType});
  final String? accountType;

  @override
  ConsumerState<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends ConsumerState<StatementScreen> {
  String? _type;
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  bool _busy = false;
  AccountPeriodStatus? _summary;
  List<(String, String)> _formats = const [];

  final _d = DateFormat('d MMM y');

  DateTimeRange get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfToday = today.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    switch (_period) {
      case _Period.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month), end: endOfToday);
      case _Period.lastMonth:
        final start = DateTime(now.year, now.month - 1);
        return DateTimeRange(
            start: start,
            end: DateTime(now.year, now.month).subtract(const Duration(milliseconds: 1)));
      case _Period.last3Months:
        return DateTimeRange(start: DateTime(now.year, now.month - 2), end: endOfToday);
      case _Period.thisYear:
        return DateTimeRange(start: DateTime(now.year), end: endOfToday);
      case _Period.custom:
        final c = _custom ?? DateTimeRange(start: today, end: today);
        return DateTimeRange(
            start: c.start,
            end: DateTime(c.end.year, c.end.month, c.end.day)
                .add(const Duration(days: 1))
                .subtract(const Duration(milliseconds: 1)));
    }
  }

  String _label(_Period p) => switch (p) {
        _Period.thisMonth => 'This month',
        _Period.lastMonth => 'Last month',
        _Period.last3Months => 'Last 3 months',
        _Period.thisYear => 'This year',
        _Period.custom => _custom == null
            ? 'Choose dates'
            : '${_d.format(_custom!.start)} – ${_d.format(_custom!.end)}',
      };

  @override
  void initState() {
    super.initState();
    _type = widget.accountType;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: _custom,
      helpText: 'Statement period',
    );
    if (r == null) return;
    setState(() {
      _custom = r;
      _period = _Period.custom;
    });
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final type = _type;
    if (type == null) return;
    setState(() => _summary = null);
    final api = ref.read(cyclosApiProvider);
    final r = _range;
    try {
      final s = await api.accountPeriod(type, r.start, r.end);
      List<(String, String)> f = const [];
      try {
        f = await api.historyExportFormats(type);
      } catch (_) {}
      if (mounted && type == _type) {
        setState(() {
          _summary = s;
          _formats = f;
        });
      }
    } on ApiException catch (_) {
      // The summary is a preview only; generating still works.
    }
  }

  Future<void> _generate({required bool print}) async {
    final type = _type;
    if (type == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(cyclosApiProvider);
      final r = _range;
      final account = _summary ?? await api.accountPeriod(type, r.start, r.end);
      final h = await api.historyAll(type, r.start, r.end);
      final who = ref.read(authProvider).user?.display ?? '';
      final name =
          'nchemty-statement-${DateFormat('yyyyMMdd').format(r.start)}-${DateFormat('yyyyMMdd').format(r.end)}.pdf';
      Future<Uint8List> build() => buildStatementPdf(
            account: account,
            entries: h.items,
            from: r.start,
            to: r.end,
            memberName: who,
            truncated: h.truncated,
          );
      if (print) {
        await Printing.layoutPdf(name: name, onLayout: (_) => build());
      } else {
        await Printing.sharePdf(bytes: await build(), filename: name);
      }
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _official(String format) async {
    final type = _type;
    if (type == null) return;
    setState(() => _busy = true);
    try {
      final r = _range;
      final bytes = await ref.read(cyclosApiProvider).exportHistory(type, format, r.start, r.end);
      await Printing.sharePdf(
          bytes: bytes,
          filename:
              'nchemty-cyclos-statement-${DateFormat('yyyyMMdd').format(r.start)}-${DateFormat('yyyyMMdd').format(r.end)}.pdf');
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final pdf = _formats.where((f) => f.$1.toLowerCase().contains('pdf')).firstOrNull;
    final r = _range;

    return Scaffold(
      appBar: AppBar(title: const Text('Account statement')),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: ErrorRetry(error: e, onRetry: () => ref.invalidate(accountsProvider))),
        data: (list) {
          if (_type == null && list.isNotEmpty) {
            _type = list.first.typeId;
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              DropdownButtonFormField<String>(
                initialValue: list.any((a) => a.typeId == _type) ? _type : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  for (final Account a in list)
                    DropdownMenuItem(
                      value: a.typeId,
                      child: Text('${a.typeName}  ${a.maskedNumber}'),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _type = v);
                  _loadSummary();
                },
              ),
              const SizedBox(height: 20),
              const Text('Period', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _Period.values)
                    ChoiceChip(
                      label: Text(_label(p)),
                      avatar: p == _Period.custom ? const Icon(Icons.date_range, size: 18) : null,
                      selected: _period == p,
                      onSelected: (_) {
                        if (p == _Period.custom) {
                          _pickCustom();
                        } else {
                          setState(() => _period = p);
                          _loadSummary();
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(children: [
                    SummaryRow('Period', '${_d.format(r.start)} – ${_d.format(r.end)}'),
                    if (_summary == null)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: LinearProgressIndicator(),
                      )
                    else ...[
                      if (_summary!.balanceAtBegin != null)
                        SummaryRow('Opening balance', Money.xaf(_summary!.balanceAtBegin!)),
                      if (_summary!.incomingSum != null)
                        SummaryRow(
                            'Money in${_summary!.incomingCount != null ? ' (${_summary!.incomingCount})' : ''}',
                            Money.xaf(_summary!.incomingSum!)),
                      if (_summary!.outgoingSum != null)
                        SummaryRow(
                            'Money out${_summary!.outgoingCount != null ? ' (${_summary!.outgoingCount})' : ''}',
                            Money.xaf(_summary!.outgoingSum!)),
                      if (_summary!.balanceAtEnd != null)
                        SummaryRow('Closing balance', Money.xaf(_summary!.balanceAtEnd!),
                            strong: true),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy || _type == null ? null : () => _generate(print: false),
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share),
                label: const Text('Share statement (PDF)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy || _type == null ? null : () => _generate(print: true),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
              ),
              if (pdf != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy ? null : () => _official(pdf.$1),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Official Cyclos statement (PDF)'),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Balances and totals come from Nchemty\'s records. Long periods may take a moment.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ],
          );
        },
      ),
    );
  }
}
