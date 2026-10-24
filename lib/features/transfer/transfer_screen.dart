import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';

/// Member-to-member transfer, following the Cyclos 4.16 flow:
///  1. GET  /self/payments/data-for-perform?to=…  → real payee + payment types
///  2. POST /self/payments/preview {subject, type, amount} → fees, total,
///     and whether/how to confirm (confirmationPasswordInput)
///  3. POST /self/payments with the `confirmationPassword` header (if asked)
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key, this.initialTo});
  final String? initialTo;

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  late final _to = TextEditingController(text: widget.initialTo);
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();

  PaymentData? _data; // step 1 result
  PaymentType? _type;
  PaymentPreview? _preview; // step 2 result
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  CyclosApi get _api => ref.read(cyclosApiProvider);

  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findPayee() async {
    if (_to.text.trim().isEmpty) return;
    await _run(() async {
      final d = await _api.paymentData(_to.text.trim());
      if (!mounted) return;
      if (d.paymentTypes.isEmpty) {
        throw ApiException(
            'You have no payment type that can pay this member. Please contact Nchemty.');
      }
      setState(() {
        _data = d;
        _type = d.paymentTypes.first;
      });
    });
  }

  Future<void> _doPreview() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final p = await _api.previewPayment(
        subject: _to.text.trim(),
        amount: Money.fromInput(_amount.text)!,
        paymentType: _type?.id,
        description: _note.text.trim(),
      );
      if (mounted) setState(() => _preview = p);
    });
  }

  Future<void> _confirm() async {
    final s = S.read(ref);
    final p = _preview!;
    String? credential;
    if (p.requiresConfirmation) {
      credential = await askConfirmationPassword(
        context,
        title: s.t('txPin'),
        input: p.confirmation,
        onSendOtp: (m) => _api.sendOtp(medium: m),
      );
      if (credential == null || credential.isEmpty || !mounted) return;
    }
    await _run(() async {
      final txNumber = await _api.performPayment(
        subject: _to.text.trim(),
        amount: Money.fromInput(_amount.text)!,
        paymentType: _type?.id,
        description: _note.text.trim(),
        confirmationPassword: credential,
      );
      if (!mounted) return;
      ref.invalidate(accountsProvider);
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.credit, size: 48),
          title: Text(s.t('success')),
          content: Text(
              '${Money.xaf(p.amount)} to ${p.recipient}\nReference: $txNumber'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c), child: Text(s.t('done'))),
          ],
        ),
      );
      if (mounted) context.pop();
    });
  }

  void _reset() => setState(() {
        _data = null;
        _type = null;
        _preview = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    final d = _data;
    final payee = d?.payee;
    final types = d?.paymentTypes ?? const <PaymentType>[];
    final p = _preview;
    final step = d == null ? 1 : (p == null ? 2 : 3);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('sendMoney'))),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Step 1: who
              TextFormField(
                controller: _to,
                enabled: step == 1,
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (_) => _findPayee(),
                decoration: InputDecoration(
                  labelText: s.t('recipient'),
                  suffixIcon: step == 1
                      ? null
                      : IconButton(
                          tooltip: 'Change',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _busy ? null : _reset,
                        ),
                ),
              ),
              if (payee != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.goldLight,
                      foregroundColor: AppColors.greenDark,
                      child: Text(payee.initials),
                    ),
                    title: Text(payee.display,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Check this is the right person'),
                  ),
                ),
              ],

              // Step 2: how much
              if (step >= 2) ...[
                if (types.length > 1) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<PaymentType>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Payment type'),
                    items: [
                      for (final t in types)
                        DropdownMenuItem(value: t, child: Text(t.name)),
                    ],
                    onChanged: step == 2 ? (t) => setState(() => _type = t) : null,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  enabled: step == 2,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(labelText: s.t('amount')),
                  validator: (v) =>
                      (Money.fromInput(v ?? '') ?? 0) <= 0 ? 'Enter an amount' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _note,
                  enabled: step == 2,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: s.t('note')),
                ),
              ],

              // Step 3: review
              if (p != null)
                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(children: [
                      SummaryRow('To', p.recipient),
                      if (p.paymentTypeName != null)
                        SummaryRow('Type', p.paymentTypeName!),
                      SummaryRow(s.t('amount'), Money.xaf(p.amount)),
                      SummaryRow(s.t('fee'), Money.xaf(p.fees)),
                      SummaryRow(s.t('total'), Money.xaf(p.totalAmount),
                          strong: true),
                    ]),
                  ),
                ),
              if (p != null && p.confirmationMessage != null) ...[
                const SizedBox(height: 12),
                Text(p.confirmationMessage!),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!.isWrongConfirmation
                      ? 'Wrong PIN or code. Please try again.'
                      : _error!.message,
                  style: const TextStyle(color: AppColors.debit),
                ),
                if (_error!.details != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => showApiError(context, _error!),
                      child: const Text('Details'),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy
                    ? null
                    : switch (step) {
                        1 => _findPayee,
                        2 => _doPreview,
                        _ => _confirm,
                      },
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(switch (step) {
                        1 => s.t('continue'),
                        2 => 'Review',
                        _ => '${s.t('send')} ${Money.xaf(p!.amount)}',
                      }),
              ),
              if (step == 3)
                TextButton(
                  onPressed:
                      _busy ? null : () => setState(() => _preview = null),
                  child: const Text('Change amount'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
