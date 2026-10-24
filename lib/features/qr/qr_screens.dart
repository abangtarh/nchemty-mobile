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

    if (qr is ReceiptQr) {
      context.pushReplacement('/verify', extra: qr);
      return;
    }

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
      case ReceiptQr():
        return null;
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
          case ReceiptQr():
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
class ReceiveQrScreen extends ConsumerWidget {
  const ReceiveQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Receive money'),
          bottom: const TabBar(
            labelColor: AppColors.green,
            indicatorColor: AppColors.green,
            tabs: [Tab(text: 'Request payment'), Tab(text: 'My QR code')],
          ),
        ),
        body: const TabBarView(children: [_RequestPaymentTab(), _MyQrTab()]),
      ),
    );
  }
}

/// Official "Receive QR payment" flow (cyclos4-ui receive-qr-payment):
/// account → type (filtered by `to.id`) → amount/description → ticket QR →
/// wait until paid. The app polls the ticket (the web uses push events).
class _RequestPaymentTab extends ConsumerStatefulWidget {
  const _RequestPaymentTab();
  @override
  ConsumerState<_RequestPaymentTab> createState() => _RequestPaymentTabState();
}

class _RequestPaymentTabState extends ConsumerState<_RequestPaymentTab>
    with AutomaticKeepAliveClientMixin {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final CyclosQrApi _api;

  bool _loading = true;
  bool _busy = false;
  ApiException? _error;

  List<Account> _accounts = const [];
  List<PaymentType> _allTypes = const [];
  Account? _account;
  PaymentType? _type;
  PaymentTypeRules? _rules;

  TicketInfo? _ticket;
  Timer? _poll;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _api = ref.read(cyclosQrApiProvider);
    Future.microtask(_init);
  }

  @override
  void dispose() {
    // Like the official app, leaving does not cancel the request: the payer
    // may still be paying. It ends when paid, cancelled, or after it expires.
    _poll?.cancel();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
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

  List<PaymentType> get _types => _allTypes
      .where((t) => t.toId == null || t.toId == _account?.typeKey)
      .toList();

  Future<void> _init() => _run(() async {
        final d = await _api.dataForNewTicket();
        if (d.accounts.isEmpty || d.paymentTypes.isEmpty) {
          throw ApiException('Your account cannot receive QR payments. Please contact Nchemty.');
        }
        if (!mounted) return;
        setState(() {
          _accounts = d.accounts;
          _allTypes = d.paymentTypes;
          _account = d.accounts.first;
        });
        await _pickType();
      });

  Future<void> _pickType([PaymentType? wanted]) async {
    final types = _types;
    if (types.isEmpty) {
      setState(() {
        _type = null;
        _rules = null;
      });
      throw ApiException('This account cannot receive QR payments.');
    }
    final t = wanted ?? types.first;
    setState(() {
      _type = t;
      _rules = null;
    });
    final d = await _api.dataForNewTicket(type: t.id);
    if (!mounted) return;
    setState(() {
      _rules = d.rules ?? PaymentTypeRules();
      final fixed = _rules!.fixedAmount;
      if (fixed != null && fixed > 0) _amount.text = fixed.round().toString();
    });
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final t = await _api.newTicket(
        type: _type!.id,
        amount: Money.fromInput(_amount.text)!,
        description: _note.text.trim(),
      );
      if (!mounted) return;
      setState(() => _ticket = t);
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    });
  }

  Future<void> _refresh() async {
    final t = _ticket;
    if (t == null) return;
    try {
      final now = await _api.ticket(t.number);
      if (!mounted) return;
      setState(() => _ticket = TicketInfo(
            number: t.number,
            status: now.status,
            amount: t.amount,
            payeeName: t.payeeName,
            description: t.description,
            approveUrl: t.approveUrl,
            transactionNumber: now.transactionNumber,
          ));
      if (!now.isOpen) {
        _poll?.cancel();
        if (now.isPaid) ref.invalidate(accountsProvider);
      }
    } on ApiException {
      // A network blip should not end the sale; keep polling.
    }
  }

  Future<void> _cancel() async {
    final t = _ticket;
    _poll?.cancel();
    if (t != null && t.isOpen) {
      await _run(() => _api.cancelTicket(t.number));
    }
    if (mounted) setState(() => _ticket = null);
  }

  void _newRequest() => setState(() {
        _ticket = null;
        _amount.clear();
        _note.clear();
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    final t = _ticket;
    return t == null ? _buildForm(context) : _buildTicket(context, t);
  }

  Widget _errorBox(BuildContext context) => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_error!.message, style: const TextStyle(color: AppColors.debit)),
            if (_error!.details != null)
              TextButton(
                  onPressed: () => showApiError(context, _error!),
                  child: const Text('Details')),
          ]),
        );

  Widget _buildForm(BuildContext context) {
    final s = S.of(ref);
    final rules = _rules;
    final descriptionMode = rules?.descriptionAvailability ?? 'optional';
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_accounts.length > 1)
            DropdownButtonFormField<Account>(
              initialValue: _account,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'To account'),
              items: [
                for (final a in _accounts)
                  DropdownMenuItem(value: a, child: Text(a.typeName)),
              ],
              onChanged: _busy
                  ? null
                  : (a) {
                      setState(() => _account = a);
                      _run(_pickType);
                    },
            ),
          if (_types.length > 1) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<PaymentType>(
              key: ValueKey(_account?.id),
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Transfer type'),
              items: [
                for (final t in _types) DropdownMenuItem(value: t, child: Text(t.name)),
              ],
              onChanged: _busy ? null : (t) => _run(() => _pickType(t)),
            ),
          ],
          if (rules != null) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              enabled: !_busy && (rules.fixedAmount ?? 0) <= 0,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              decoration: InputDecoration(labelText: s.t('amount')),
              validator: (v) =>
                  (Money.fromInput(v ?? '') ?? 0) <= 0 ? 'Enter an amount' : null,
            ),
            if (descriptionMode != 'disabled') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                enabled: !_busy,
                maxLength: 100,
                decoration: InputDecoration(
                    labelText: descriptionMode == 'required' ? 'Description' : s.t('note')),
                validator: (v) => descriptionMode == 'required' && (v == null || v.trim().isEmpty)
                    ? 'A description is required'
                    : null,
              ),
            ],
          ],
          _errorBox(context),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy || rules == null ? null : _create,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Show QR code'),
          ),
          const SizedBox(height: 12),
          const Text(
            'The payer scans this code with the Nchemty app and confirms. Keep this screen open to see when the money arrives; the request stays valid for a day unless you cancel it.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildTicket(BuildContext context, TicketInfo t) {
    final paid = t.isPaid;
    final ended = !t.isOpen && !paid;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(Money.xaf(t.amount),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              if (t.description?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t.description!, style: const TextStyle(color: AppColors.muted)),
                ),
              const SizedBox(height: 16),
              if (paid)
                const SizedBox(
                  height: 240,
                  child: Center(
                      child: Icon(Icons.check_circle, color: AppColors.credit, size: 120)),
                )
              else
                Opacity(
                  opacity: ended ? 0.25 : 1,
                  child: Image.network(
                    _api.ticketQrUrl(t.number),
                    headers: _api.imageHeaders,
                    width: 240,
                    height: 240,
                    semanticLabel: 'QR code to pay ${Money.xaf(t.amount)}',
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 240,
                        height: 240,
                        child: Center(child: Text('Could not load the QR code'))),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (t.isOpen) ...[
                    const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    paid
                        ? 'Paid'
                        : t.isOpen
                            ? 'Waiting for payment…'
                            : 'This request ${t.status}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: paid ? AppColors.credit : AppColors.ink),
                  ),
                ],
              ),
              if (paid && t.transactionNumber != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Reference: ${t.transactionNumber}',
                      style: const TextStyle(color: AppColors.muted)),
                ),
                TextButton.icon(
                  onPressed: () => context.push(
                      '/transfer-details/${Uri.encodeComponent(CyclosApi.escapeNumeric(t.transactionNumber!))}'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View receipt'),
                ),
              ],
            ]),
          ),
        ),
        _errorBox(context),
        const SizedBox(height: 16),
        if (t.isOpen) ...[
          if (t.approveUrl != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: t.approveUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payment link copied')));
              },
              icon: const Icon(Icons.link),
              label: const Text('Copy payment link'),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancel request'),
          ),
        ] else
          FilledButton(onPressed: _newRequest, child: const Text('New request')),
      ],
    );
  }
}

/// The member's permanent "pay me" QR: their QR token if Cyclos issued one
/// (the same codes as /pay/... links), else an easy-invoice QR with an
/// optional amount.
class _MyQrTab extends ConsumerStatefulWidget {
  const _MyQrTab();
  @override
  ConsumerState<_MyQrTab> createState() => _MyQrTabState();
}

class _MyQrTabState extends ConsumerState<_MyQrTab>
    with AutomaticKeepAliveClientMixin {
  final _amount = TextEditingController();
  late final CyclosQrApi _api;
  bool _loading = true;
  String? _tokenId;
  int? _requested;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _api = ref.read(cyclosQrApiProvider);
    Future.microtask(() async {
      String? id;
      try {
        id = await _api.myQrTokenId();
      } on ApiException {
        id = null; // fall back to the easy-invoice QR
      }
      if (mounted) {
        setState(() {
          _tokenId = id;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = ref.watch(authProvider.select((a) => a.user));
    if (_loading) return const Center(child: CircularProgressIndicator());
    // A fixed amount needs the easy-invoice QR; the token QR has none.
    final useToken = _tokenId != null && (_requested ?? 0) <= 0;
    final url = useToken
        ? _api.tokenQrUrl(_tokenId!)
        : (user == null ? null : _api.easyInvoiceQrUrl(user.id, amount: _requested));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(user?.display ?? '',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (url != null)
                Image.network(
                  url,
                  key: ValueKey(url),
                  headers: _api.imageHeaders,
                  width: 240,
                  height: 240,
                  semanticLabel: 'Your QR code for receiving payments',
                  errorBuilder: (_, __, ___) => const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(child: Text('Could not load the QR code'))),
                ),
              if ((_requested ?? 0) > 0) ...[
                const SizedBox(height: 12),
                Text(Money.xaf(_requested),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Ask for an amount (optional)'),
          onChanged: (v) => setState(() => _requested = Money.fromInput(v)),
        ),
        const SizedBox(height: 12),
        const Text(
          'Anyone with the Nchemty app can scan this code to pay you. For a sale, use Request payment so you see when it is paid.',
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    );
  }
}
