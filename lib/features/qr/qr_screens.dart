import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/cyclos/cyclos_qr_api.dart';
import '../auth/auth_controller.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';

/// Scan a Cyclos QR (easy invoice or ticket), check the payee Cyclos
/// returns (never the name inside the QR), then pay with the transaction PIN.
class ScanToPayScreen extends ConsumerStatefulWidget {
  const ScanToPayScreen({super.key});
  @override
  ConsumerState<ScanToPayScreen> createState() => _ScanToPayScreenState();
}

class _ScanToPayScreenState extends ConsumerState<ScanToPayScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    final qr = ScannedQr.parse(raw);
    if (qr == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This is not a Nchemty payment QR.')));
      return;
    }
    _handling = true;
    await _controller.stop();
    if (!mounted) return;
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QrPaymentSheet(qr: qr),
    );
    if (!mounted) return;
    if (paid == true) {
      ref.invalidate(accountsProvider);
      context.pop();
    } else {
      _handling = false;
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan to pay',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.gold, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 32,
            child: Column(
              children: [
                const Text(
                  'Point at a Nchemty QR code. You will check the name and amount before paying.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.goldLight),
                  onPressed: () => context.pushReplacement('/qr/receive'),
                  child: const Text('Show my QR to receive'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrPaymentSheet extends ConsumerStatefulWidget {
  const _QrPaymentSheet({required this.qr});
  final ScannedQr qr;
  @override
  ConsumerState<_QrPaymentSheet> createState() => _QrPaymentSheetState();
}

class _QrPaymentSheetState extends ConsumerState<_QrPaymentSheet> {
  final _amount = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _payee = '';
  num? _fixedAmount;
  num? _fees;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// What the QR turned out to be once Cyclos was asked.
  late ScannedQr _resolved = widget.qr;

  /// A /pay/{code} link may be a ticket or an easy invoice: ask Cyclos for
  /// a ticket with that number first; if none exists, treat it as an
  /// easy invoice to that user.
  Future<ScannedQr> _resolve(ScannedQr qr) async {
    if (qr is! PayLinkQr) return qr;
    try {
      await ref.read(cyclosQrApiProvider).ticket(qr.code);
      return TicketQr(qr.code);
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 422) {
        return EasyInvoiceQr(qr.code,
            amount: qr.amount, description: qr.description);
      }
      rethrow;
    }
  }

  Future<void> _load() async {
    try {
      _resolved = await _resolve(widget.qr);
      switch (_resolved) {
        case TicketQr(:final number):
          final t = await ref.read(cyclosQrApiProvider).ticket(number);
          if (!t.isOpen) throw ApiException('This QR has already been used or has expired.');
          final preview = await ref.read(cyclosQrApiProvider).previewTicket(number);
          final fees = (preview['fees'] as List?) ?? const [];
          if (!mounted) return;
          setState(() {
            _payee = t.payeeName;
            _fixedAmount = t.amount;
            _fees = fees.fold<num>(0, (s, f) => s + Money.parse((f as Map)['amount']));
          });
        case EasyInvoiceQr(:final to, :final amount):
          _fixedAmount = amount;
          // Preview resolves the real payee in Cyclos. Amount 1 is only to
          // resolve the name when the QR carries no amount.
          final p = await ref
              .read(cyclosApiProvider)
              .previewPayment(subject: to, amount: amount ?? 1);
          if (!mounted) return;
          setState(() {
            _payee = p.recipient;
            _fees = amount == null ? null : p.fees;
          });
        case PayLinkQr():
          break; // resolved above
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    final amount = _fixedAmount ?? Money.fromInput(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    final pin = await askConfirmationPassword(context, title: S.read(ref).t('txPin'));
    if (pin == null || pin.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_resolved) {
        case PayLinkQr():
          throw ApiException('Could not read this QR code.');
        case TicketQr(:final number):
          await ref.read(cyclosQrApiProvider).approveTicket(number, pin);
        case EasyInvoiceQr(:final to, :final description):
          await ref.read(cyclosApiProvider).performPayment(
                subject: to,
                amount: amount,
                description: description,
                confirmationPassword: pin,
              );
      }
      if (mounted) Navigator.pop(context, true);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: _loading
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_payee.isEmpty ? 'Payment' : 'Pay $_payee',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (_fixedAmount != null)
                  Text(Money.xaf(_fixedAmount),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))
                else
                  TextField(
                    controller: _amount,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(labelText: s.t('amount')),
                  ),
                if (_fees != null && _fees! > 0)
                  SummaryRow(s.t('fee'), Money.xaf(_fees)),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.debit)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _payee.isEmpty ? null : _pay,
                  child: Text(s.t('confirm')),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Shows the member's Cyclos easy-invoice QR (optionally with an amount),
/// or creates a one-off ticket for agents and shops.
class ReceiveQrScreen extends ConsumerStatefulWidget {
  const ReceiveQrScreen({super.key});
  @override
  ConsumerState<ReceiveQrScreen> createState() => _ReceiveQrScreenState();
}

class _ReceiveQrScreenState extends ConsumerState<ReceiveQrScreen> {
  final _amount = TextEditingController();
  int? _requested;
  String? _ticket;
  String? _ticketStatus;
  Timer? _poll;
  String? _error;
  // Captured up front: `ref` must not be used in dispose().
  late final CyclosQrApi _api;

  @override
  void initState() {
    super.initState();
    _api = ref.read(cyclosQrApiProvider);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    final t = _ticket;
    if (t != null && _ticketStatus == 'open') {
      // Leave no open ticket behind.
      _api.cancelTicket(t).ignore();
    }
    super.dispose();
  }

  Future<void> _createTicket() async {
    final amount = Money.fromInput(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount to charge.');
      return;
    }
    setState(() => _error = null);
    try {
      final api = _api;
      final number = await api.createTicket(amount: amount);
      if (!mounted) {
        api.cancelTicket(number).ignore();
        return;
      }
      setState(() {
        _ticket = number;
        _ticketStatus = 'open';
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          final t = await api.ticket(number);
          if (!mounted) return;
          setState(() => _ticketStatus = t.status.toLowerCase());
          if (!t.isOpen) {
            _poll?.cancel();
            ref.invalidate(accountsProvider);
          }
        } on ApiException {
          // Keep polling; a network blip should not end the sale.
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider.select((a) => a.user));
    final api = _api;
    final main = ref.watch(mainAccountProvider).valueOrNull;
    final ticket = _ticket;
    final qrUrl = ticket != null
        ? api.ticketQrUrl(ticket)
        : (user == null ? null : api.easyInvoiceQrUrl(user.id, amount: _requested));

    return Scaffold(
      backgroundColor: AppColors.green,
      appBar: AppBar(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        title: const Text('Receive money',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(user?.display ?? '',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    if (main != null)
                      Text('${main.typeName} ${main.maskedNumber}',
                          style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 16),
                    if (qrUrl != null)
                      Image.network(
                        qrUrl,
                        key: ValueKey(qrUrl),
                        headers: api.imageHeaders,
                        width: 232,
                        height: 232,
                        semanticLabel: 'QR code for receiving a payment',
                        errorBuilder: (_, __, ___) => const SizedBox(
                            width: 232,
                            height: 232,
                            child: Center(child: Text('Could not load the QR code'))),
                      ),
                    const SizedBox(height: 12),
                    if (ticket != null)
                      Text(switch (_ticketStatus) {
                        'open' => 'Waiting for the customer to pay…',
                        'processed' || 'approved' => 'Paid',
                        _ => 'Ticket ${_ticketStatus ?? ''}',
                      },
                          style: const TextStyle(fontWeight: FontWeight.w700))
                    else if (_requested != null)
                      Text(Money.xaf(_requested),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (ticket == null) ...[
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Ask for an amount (optional)'),
                onChanged: (v) => setState(() => _requested = Money.fromInput(v)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.goldLight)),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _createTicket,
                child: const Text('Charge a customer (one-time QR)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
