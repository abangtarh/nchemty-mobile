import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_qr_api.dart';
import '../../data/cyclos/receipt_verify_api.dart';
import '../common/widgets.dart';

/// Checks a receipt against Cyclos through the public verify-receipt service.
/// Opened from Scan (receipt QR) or the menu (typed reference + amount).
class VerifyReceiptScreen extends ConsumerStatefulWidget {
  const VerifyReceiptScreen({super.key, this.scanned});
  final ReceiptQr? scanned;

  @override
  ConsumerState<VerifyReceiptScreen> createState() => _VerifyReceiptScreenState();
}

class _VerifyReceiptScreenState extends ConsumerState<VerifyReceiptScreen> {
  late final _refCtrl = TextEditingController(text: widget.scanned?.reference ?? '');
  late final _amount = TextEditingController(
      text: widget.scanned?.amount == null ? '' : '${widget.scanned!.amount!.round()}');
  bool _busy = false;
  ReceiptVerification? _result;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    if (widget.scanned?.amount != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final amount = num.tryParse(_amount.text.replaceAll(RegExp(r'[\s,]'), ''));
    if (_refCtrl.text.trim().isEmpty || amount == null) {
      setState(() => _error = ApiException('Enter the reference and the amount shown on the receipt.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await ref.read(receiptVerifyApiProvider).verify(_refCtrl.text, amount);
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify a receipt')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Scan the QR code on a receipt, or type the reference and amount printed on it.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(labelText: 'Reference'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount (XAF)'),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _verify,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_outlined),
            label: const Text('Verify'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => context.pushReplacement('/qr/scan'),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan a receipt'),
          ),
          const SizedBox(height: 20),
          if (_error != null) ErrorRetry(error: _error!, onRetry: _verify),
          if (_result != null) _ResultCard(r: _result!, amountTyped: _amount.text),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.r, required this.amountTyped});
  final ReceiptVerification r;
  final String amountTyped;

  @override
  Widget build(BuildContext context) {
    final ok = r.valid;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: ok ? AppColors.credit : const Color(0xFFB3261E),
              foregroundColor: Colors.white,
              child: Icon(ok ? Icons.check : Icons.priority_high, size: 30),
            ),
            const SizedBox(height: 10),
            Text(ok ? 'Genuine receipt' : 'Not verified',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              ok
                  ? 'Nchemty recorded this transaction. Check that every detail on the slip matches.'
                  : 'No Nchemty transaction matches this reference and amount. The receipt may have been altered.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            if (ok && r.reversed) ...[
              const SizedBox(height: 10),
              const Text('This transaction was later reversed.',
                  style: TextStyle(color: AppColors.debit, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            SummaryRow('Reference', r.reference, strong: true),
            if (ok) ...[
              if (r.amount != null) SummaryRow('Amount', Money.xaf(r.amount!)),
              if (r.dateText != null) SummaryRow('Date', r.dateText!),
              if (r.type != null) SummaryRow('Type', r.type!),
              if (r.from != null) SummaryRow('From', r.from!),
              if (r.to != null) SummaryRow('To', r.to!),
            ] else
              SummaryRow('Amount checked', '$amountTyped XAF'),
          ],
        ),
      ),
    );
  }
}
