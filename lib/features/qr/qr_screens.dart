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
import '../../data/models/models.dart';
import '../auth/auth_controller.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';
import '../transfer/transfer_screen.dart';

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
          const SnackBar(content: Text('This QR code is not from Nchemty.')));
      return;
    }
    _handling = true;
    await _controller.stop();
    if (!mounted) return;

    _Resolved? r;
    ApiException? error;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      r = await _resolve(qr);
    } on ApiException catch (e) {
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // progress

    if (r?.ticket != null) {
      final paid = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _QrPaymentSheet(qr: TicketQr(r!.ticket!)),
      );
      if (!mounted) return;
      if (paid == true) {
        ref.invalidate(accountsProvider);
        context.pop();
        return;
      }
    } else if (r?.args != null) {
      context.pushReplacement('/transfer', extra: r!.args);
      return;
    } else {
      await showApiError(context,
          error ?? ApiException('No member or payment matches this QR code.'),
          title: 'Could not read this QR code');
    }
    _handling = false;
    await _controller.start();
  }

  /// Same idea as the official frontend: a ticket is paid as a ticket;
  /// anything else identifies the payee (`*:<value>` matches any principal,
  /// QR tokens included) and continues in the normal Send form.
  Future<_Resolved?> _resolve(ScannedQr qr) async {
    final api = ref.read(cyclosApiProvider);
    final qrApi = ref.read(cyclosQrApiProvider);

    Future<bool> isTicket(String code) async {
      try {
        await qrApi.ticket(code);
        return true;
      } on ApiException catch (e) {
        if (e.isNotFound || e.statusCode == 422 || e.statusCode == 403) return false;
        rethrow;
      }
    }

    Future<CyclosUser?> locate(String value) async {
      try {
        return await api.locateUser('*:$value');
      } on ApiException catch (e) {
        if (e.isNotFound || e.statusCode == 422) return null;
        rethrow;
      }
    }

    Future<CyclosUser?> easyInvoicePayee(String to) async {
      try {
        return (await qrApi.easyInvoiceData(to)).payee;
      } on ApiException catch (e) {
        if (e.isNotFound || e.statusCode == 422) return null;
        rethrow;
      }
    }

    switch (qr) {
      case TicketQr(:final number):
        return _Resolved(ticket: number);
      case PayLinkQr(:final code, :final amount, :final description):
        if (await isTicket(code)) return _Resolved(ticket: code);
        final u = await locate(code) ?? await easyInvoicePayee(code);
        return u == null
            ? null
            : _Resolved(args: TransferArgs(payee: u, amount: amount, description: description));
      case EasyInvoiceQr(:final to, :final amount, :final description):
        final u = await easyInvoicePayee(to) ?? await locate(to);
        return u == null
            ? null
            : _Resolved(args: TransferArgs(payee: u, amount: amount, description: description));
      case PrincipalQr(:final value):
        if (value.length >= 20 && await isTicket(value)) return _Resolved(ticket: value);
        final u = await locate(value);
        return u == null ? null : _Resolved(args: TransferArgs(payee: u));
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
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Allow it in Settings > Apps > Nchemty > Permissions, then try again.'
                      : 'The camera could not start (${error.errorCode.name}). ${error.errorDetails?.message ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
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

class _Resolved {
  _Resolved({this.ticket, this.args});
  final String? ticket;
  final TransferArgs? args;
}

class _QrPaymentSheet extends ConsumerStatefulWidget {
  const _QrPaymentSheet({required this.qr});
  final ScannedQr qr;
  @override
  ConsumerState<_QrPaymentSheet> createState() => _QrPaymentSheetState();
}

/// Resolves the scanned code with Cyclos, previews, then pays:
///  * ticket       -> GET /tickets/{n}, POST /tickets/{n}/preview, /approve
///  * easy invoice -> GET /easy-invoices/data-for-perform/{to},
///                    POST /easy-invoices/preview, POST /easy-invoices
class _QrPaymentSheetState extends ConsumerState<_QrPaymentSheet> {
  final _amount = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  ApiException? _error;

  String? _ticket; // set when the code is an open ticket
  String? _to; // set when the code is an easy invoice
  String? _description;
  String _payee = '';
  num? _fixedAmount;
  PaymentType? _type;
  PaymentPreview? _preview;

  CyclosQrApi get _api => ref.read(cyclosQrApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load); // not during initState: _guard calls setState
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  /// A /pay/{code} link is a ticket if Cyclos knows a ticket with that
  /// number; otherwise it is treated as an easy invoice to that user.
  Future<void> _load() => _guard(() async {
        switch (widget.qr) {
          case TicketQr(:final number):
            return _loadTicket(number);
          case EasyInvoiceQr(:final to, :final amount, :final description):
            return _loadEasy(to, amount, description);
          case PrincipalQr():
            throw ApiException('This QR code is not a payment.');
          case PayLinkQr(:final code, :final amount, :final description):
            TicketInfo? found;
            try {
              found = await _api.ticket(code);
            } on ApiException catch (e) {
              if (!(e.isNotFound || e.statusCode == 422)) rethrow;
            }
            return found != null
                ? _loadTicket(code)
                : _loadEasy(code, amount, description);
        }
      });

  Future<void> _loadTicket(String number) async {
    final t = await _api.ticket(number);
    if (!t.isOpen) {
      throw ApiException('This QR has already been used or has expired.');
    }
    final preview = await _api.previewTicket(number);
    if (!mounted) return;
    setState(() {
      _ticket = number;
      _payee = t.payeeName.isNotEmpty ? t.payeeName : preview.recipient;
      _fixedAmount = t.amount;
      _preview = preview;
    });
  }

  Future<void> _loadEasy(String to, num? amount, String? description) async {
    final d = await _api.easyInvoiceData(to, amount: amount);
    if (d.paymentTypes.isEmpty) {
      throw ApiException('You cannot pay this member from your accounts.');
    }
    if (!mounted) return;
    setState(() {
      _to = to;
      _description = description;
      _payee = d.payee?.display ?? '';
      _fixedAmount = (amount ?? d.amount) != null && (amount ?? d.amount)! > 0
          ? (amount ?? d.amount)
          : null;
      _type = d.paymentTypes.first;
    });
    if (_fixedAmount != null) await _previewEasy();
  }

  num? get _amountValue => _fixedAmount ?? Money.fromInput(_amount.text);

  Future<void> _previewEasy() async {
    final amount = _amountValue;
    if (amount == null || amount <= 0) {
      setState(() => _error = ApiException('Enter an amount.'));
      return;
    }
    final p = await _api.previewEasyInvoice(
        to: _to!, amount: amount, type: _type?.id, description: _description);
    if (mounted) setState(() => _preview = p);
  }

  Future<void> _pay() async {
    final p = _preview;
    if (p == null) return _guard(_previewEasy);
    String? credential;
    if (p.requiresConfirmation) {
      credential = await askConfirmationPassword(
        context,
        title: S.read(ref).t('txPin'),
        input: p.confirmation,
        onSendOtp: (m) => ref.read(cyclosApiProvider).sendOtp(medium: m),
      );
      if (credential == null || credential.isEmpty || !mounted) return;
    }
    await _guard(() async {
      if (_ticket != null) {
        await _api.approveTicket(_ticket!, credential);
      } else {
        await _api.payEasyInvoice(
          to: _to!,
          amount: _amountValue!,
          type: _type?.id,
          description: _description,
          confirmationPassword: credential,
        );
      }
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    final p = _preview;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: _loading
          ? const SizedBox(
              height: 160, child: Center(child: CircularProgressIndicator()))
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
                else if (_to != null)
                  TextField(
                    controller: _amount,
                    autofocus: true,
                    enabled: p == null,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(labelText: s.t('amount')),
                  ),
                if (p != null) ...[
                  SummaryRow(s.t('fee'), Money.xaf(p.fees)),
                  SummaryRow(s.t('total'), Money.xaf(p.totalAmount), strong: true),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                      _error!.isWrongConfirmation
                          ? 'Wrong PIN or code. Please try again.'
                          : _error!.message,
                      style: const TextStyle(color: AppColors.debit)),
                  if (_error!.details != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => showApiError(context, _error!),
                        child: const Text('Details'),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || (_ticket == null && _to == null) ? null : _pay,
                  child: Text(p == null ? 'Review' : s.t('confirm')),
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
