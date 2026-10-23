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

/// Member-to-member transfer straight on Cyclos:
/// form -> POST /self/payments/preview -> PIN -> POST /self/payments.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final _to = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();
  PaymentPreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _doPreview() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ref.read(cyclosApiProvider).previewPayment(
            subject: _to.text.trim(),
            amount: Money.fromInput(_amount.text)!,
            description: _note.text.trim(),
          );
      if (mounted) setState(() => _preview = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final s = S.read(ref);
    final pin = await askConfirmationPassword(context, title: s.t('txPin'));
    if (pin == null || pin.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final txNumber = await ref.read(cyclosApiProvider).performPayment(
            subject: _to.text.trim(),
            amount: Money.fromInput(_amount.text)!,
            description: _note.text.trim(),
            confirmationPassword: pin,
          );
      if (!mounted) return;
      ref.invalidate(accountsProvider);
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.credit, size: 48),
          title: Text(s.t('success')),
          content: Text('Reference: $txNumber'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c),
                child: Text(s.t('done'))),
          ],
        ),
      );
      if (mounted) context.pop();
    } on ApiException catch (e) {
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
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('sendMoney'))),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _to,
                enabled: p == null,
                decoration: InputDecoration(labelText: s.t('recipient')),
                validator: (v) => (v == null || v.trim().isEmpty) ? '' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                enabled: p == null,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                decoration: InputDecoration(labelText: s.t('amount')),
                validator: (v) =>
                    (Money.fromInput(v ?? '') ?? 0) <= 0 ? '' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                enabled: p == null,
                maxLength: 100,
                decoration: InputDecoration(labelText: s.t('note')),
              ),
              if (p != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(children: [
                      SummaryRow('To', p.recipient),
                      SummaryRow(s.t('amount'), Money.xaf(p.amount)),
                      SummaryRow(s.t('fee'), Money.xaf(p.fees)),
                      SummaryRow(s.t('total'), Money.xaf(p.totalAmount), strong: true),
                    ]),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.debit)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : (p == null ? _doPreview : _confirm),
                child: Text(p == null
                    ? s.t('continue')
                    : '${s.t('send')} ${Money.xaf(p.amount)}'),
              ),
              if (p != null)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _preview = null),
                  child: const Text('Edit'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
