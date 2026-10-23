import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/middleware/hub_api.dart';
import '../../data/models/models.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';

/// Cameroon MTN numbers: 9 digits starting with 6. Sent as 2376XXXXXXXX.
String? normaliseMsisdn(String input) {
  var d = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('237')) d = d.substring(3);
  if (d.length != 9 || !d.startsWith('6')) return null;
  return '237$d';
}

class _MsisdnField extends StatelessWidget {
  const _MsisdnField({required this.controller, required this.label, this.enabled = true});
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
        decoration: InputDecoration(labelText: label, prefixText: '+237 '),
        validator: (v) =>
            normaliseMsisdn(v ?? '') == null ? 'Enter a 9-digit MTN number' : null,
      );
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.label, this.enabled = true});
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        decoration: InputDecoration(labelText: label),
        validator: (v) => (Money.fromInput(v ?? '') ?? 0) <= 0 ? '' : null,
      );
}

/// Polls the hub until the MoMo request settles (ACK state machine server-side).
Future<MomoRequest> _pollUntilSettled(HubApi hub, MomoRequest first) async {
  var current = first;
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (current.status == MomoStatus.pending && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 4));
    current = await hub.momoStatus(current.id);
  }
  return current;
}

// ---------------------------------------------------------------------------

class TopupScreen extends ConsumerStatefulWidget {
  const TopupScreen({super.key});
  @override
  ConsumerState<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends ConsumerState<TopupScreen> {
  final _msisdn = TextEditingController();
  final _amount = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _msisdn.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final s = S.read(ref);
    final hub = ref.read(hubApiProvider);
    setState(() {
      _busy = true;
      _status = s.t('approvePrompt');
    });
    try {
      final req = await hub.momoTopup(
        msisdn: normaliseMsisdn(_msisdn.text)!,
        amount: Money.fromInput(_amount.text)!,
        idempotencyKey: HubApi.newIdempotencyKey(),
      );
      final done = await _pollUntilSettled(hub, req);
      if (!mounted) return;
      ref.invalidate(accountsProvider);
      setState(() => _status = switch (done.status) {
            MomoStatus.successful => 'Top-up received.',
            MomoStatus.failed => done.message ?? 'The top-up was not approved.',
            MomoStatus.pending =>
              'Still waiting for MTN. We will notify you when it completes.',
          });
    } on ApiException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    return Scaffold(
      appBar: AppBar(title: Text('${s.t('topUp')} · MTN MoMo')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _MsisdnField(controller: _msisdn, label: s.t('momoNumber'), enabled: !_busy),
              const SizedBox(height: 16),
              _AmountField(controller: _amount, label: s.t('amount'), enabled: !_busy),
              const SizedBox(height: 16),
              if (_status != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5)),
                        ),
                      Expanded(child: Text(_status!)),
                    ]),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(s.t('continue')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Cash-out: quote (fee computed by the hub's tiered rules) -> PIN -> payout.
class CashoutScreen extends ConsumerStatefulWidget {
  const CashoutScreen({super.key});
  @override
  ConsumerState<CashoutScreen> createState() => _CashoutScreenState();
}

class _CashoutScreenState extends ConsumerState<CashoutScreen> {
  final _msisdn = TextEditingController();
  final _amount = TextEditingController();
  final _form = GlobalKey<FormState>();
  CashoutQuote? _quote;
  bool _busy = false;
  String? _error;
  // One key per quote: reusing a single key for the whole screen would make
  // the hub replay the first cash-out's result for a later, different quote.
  String _idempotencyKey = HubApi.newIdempotencyKey();

  @override
  void dispose() {
    _msisdn.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _getQuote() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final q = await ref.read(hubApiProvider).cashoutQuote(
            msisdn: normaliseMsisdn(_msisdn.text)!,
            amount: Money.fromInput(_amount.text)!,
          );
      if (!mounted) return;
      setState(() {
        _quote = q;
        _idempotencyKey = HubApi.newIdempotencyKey();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final q = _quote!;
    if (DateTime.now().isAfter(q.expiresAt)) {
      setState(() => _quote = null);
      return _getQuote();
    }
    final pin = await askConfirmationPassword(context, title: S.read(ref).t('txPin'));
    if (pin == null || pin.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final hub = ref.read(hubApiProvider);
    try {
      final req = await hub.cashout(
        quoteId: q.quoteId,
        confirmationPassword: pin,
        idempotencyKey: _idempotencyKey,
      );
      final done = await _pollUntilSettled(hub, req);
      if (!mounted) return;
      ref.invalidate(accountsProvider);
      final ok = done.status != MomoStatus.failed;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(ok ? Icons.check_circle : Icons.error_outline,
              color: ok ? AppColors.credit : AppColors.debit, size: 48),
          title: Text(switch (done.status) {
            MomoStatus.successful => 'Sent to MoMo',
            MomoStatus.pending => 'Processing',
            MomoStatus.failed => 'Cash-out failed',
          }),
          content: Text(done.message ??
              (done.status == MomoStatus.failed
                  ? 'Your account was not debited.'
                  : '${Money.xaf(q.amount)} to +${normaliseMsisdn(_msisdn.text)}')),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        ),
      );
      if (!mounted) return;
      if (ok) context.pop();
    } on ApiException catch (e) {
      // A rejected PIN moved no money; use a fresh key so the hub does not
      // replay the stored "wrong PIN" result when the member retries.
      if (e.isWrongConfirmation) _idempotencyKey = HubApi.newIdempotencyKey();
      if (mounted) {
        setState(() => _error =
            e.isWrongConfirmation ? 'Wrong transaction PIN.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    final q = _quote;
    return Scaffold(
      appBar: AppBar(title: Text('${s.t('cashOut')} · MTN MoMo')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _MsisdnField(
                  controller: _msisdn, label: s.t('momoNumber'), enabled: q == null),
              const SizedBox(height: 16),
              _AmountField(controller: _amount, label: s.t('amount'), enabled: q == null),
              if (q != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(children: [
                      SummaryRow(s.t('youReceive'), Money.xaf(q.amount)),
                      SummaryRow(s.t('fee'), Money.xaf(q.fee)),
                      SummaryRow(s.t('total'), Money.xaf(q.total), strong: true),
                    ]),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.debit)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : (q == null ? _getQuote : _confirm),
                child: Text(q == null ? s.t('continue') : s.t('confirm')),
              ),
              if (q != null)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _quote = null),
                  child: const Text('Edit'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
