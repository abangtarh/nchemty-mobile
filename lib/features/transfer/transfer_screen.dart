import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';

/// What the Send screen can start with (e.g. from a scanned QR).
class TransferArgs {
  const TransferArgs({this.payee, this.amount, this.description, this.toSelf = false});
  final CyclosUser? payee;

  /// Open in "Between my accounts" mode.
  final bool toSelf;
  final num? amount;
  final String? description;
}

enum _When { now, onDate, installments, recurring }

/// Member-to-member payment, in the same order as the official Cyclos
/// frontend (cyclos4-ui `payment-step-form`):
///  1. From account  — data-for-perform (no args) gives the accounts
///  2. Payee         — quick search (GET /users?keywords=) or a typed
///                     identifier (numeric values escaped with `'`)
///  3. Payment type  — data-for-perform?to= ; filtered by from.id
///  4. Type rules    — data-for-perform?to=&type= (fixed amount, scheduling,
///                     description required…)
///  5. Amount, description, timing → preview → confirm (only if Cyclos asks)
///     → perform with the preview's normalised payment.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key, this.args});
  final TransferArgs? args;

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _count = TextEditingController(text: '2');
  final _every = TextEditingController(text: '1');
  final _occurrences = TextEditingController();
  final _form = GlobalKey<FormState>();

  bool _loading = true;
  bool _busy = false;
  ApiException? _error;

  List<Account> _accounts = const [];
  PaymentData? _start; // data-for-perform before a payee: identification methods

  /// Transfers between the member's own accounts (data-for-perform?to=self):
  /// only the types Cyclos enables, e.g. Member account → Savings account.
  List<PaymentType> _selfTypes = const [];
  bool _toSelf = false;
  Account? _from;
  CyclosUser? _payee;
  String? _payeeLocator; // what is sent as `to` / `subject`
  List<PaymentType> _allTypes = const [];
  PaymentType? _type;
  PaymentTypeRules? _rules;

  _When _when = _When.now;
  DateTime? _date;
  String _unit = 'months';
  bool _untilCancelled = true;

  PaymentPreview? _preview;

  CyclosApi get _api => ref.read(cyclosApiProvider);

  @override
  void initState() {
    super.initState();
    final a = widget.args;
    if (a?.amount != null) _amount.text = a!.amount!.round().toString();
    if (a?.description != null) _note.text = a!.description!;
    Future.microtask(_init);
  }

  @override
  void dispose() {
    for (final c in [_amount, _note, _count, _every, _occurrences]) {
      c.dispose();
    }
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

  // 1. accounts
  Future<void> _init() => _run(() async {
        final d = await _api.paymentData();
        if (d.accounts.isEmpty) {
          throw ApiException('You have no account that can make payments.');
        }
        final preferred = ref.read(mainAccountProvider).valueOrNull;
        if (!mounted) return;
        setState(() {
          _start = d;
          _accounts = d.accounts;
          _from = d.accounts.firstWhere((a) => a.id == preferred?.id,
              orElse: () => d.accounts.first);
        });
        // Own-account transfers enabled for this member (none: mode hidden).
        try {
          final self = await _api.paymentData(to: 'self');
          if (mounted) setState(() => _selfTypes = self.paymentTypes);
        } on ApiException catch (_) {
          // No permission for payments to self.
        }
        final p = widget.args?.payee;
        if (p != null) {
          await _choosePayee(p, p.id);
        } else if (widget.args?.toSelf == true && _selfTypes.isNotEmpty) {
          await _setMode(true);
        }
      });

  /// Switches between paying a member and moving money between own accounts.
  Future<void> _setMode(bool toSelf) async {
    setState(() {
      _toSelf = toSelf;
      _payee = null;
      _payeeLocator = toSelf ? 'self' : null;
      _allTypes = toSelf ? _selfTypes : const [];
      _type = null;
      _rules = null;
      _preview = null;
      _error = null;
    });
    if (toSelf) {
      // Start from an account that can send to another of the member's accounts.
      final from = _from;
      if (from != null && !_selfTypes.any((t) => t.fromId == null || t.fromId == from.typeKey)) {
        final usable = _accounts
            .where((a) => _selfTypes.any((t) => t.fromId == a.typeKey))
            .firstOrNull;
        if (usable != null) setState(() => _from = usable);
      }
      await _run(_pickFirstType);
    }
  }

  /// Finds the payee by phone / e-mail / login name:
  ///  1. the exact identification method (`mobilePhone:677…`), when Cyclos
  ///     allows it on this channel;
  ///  2. Cyclos's general lookup (`*:value`, every method it allows);
  /// Members are never searched or listed by name (privacy): the payer must
  /// know the payee's exact phone, e-mail or login name.
  Future<({CyclosUser user, String locator})> _findPayee(
      PrincipalTypeInput type, String value) async {
    final v = value.trim();

    // Like the Cyclos web: give the identifier straight to the payment
    // (data-for-perform?to=mobilePhone:677…). This only needs permission to
    // pay the member, not to view their profile, which /locate requires.
    Future<CyclosUser?> asPayee(String locator) async {
      try {
        return (await _api.paymentData(to: locator)).payee;
      } on ApiException catch (e) {
        // Network or server failure: report it, don't mask it as "not found".
        if (e.statusCode == null || e.statusCode! >= 500) rethrow;
        return null;
      }
    }

    Future<CyclosUser?> located(String locator) async {
      try {
        return await _api.locateUser(locator);
      } on ApiException catch (e) {
        if (e.statusCode == null || e.statusCode! >= 500) rethrow;
        return null;
      }
    }

    // Each spelling (phones: 677…, +237677…, 237677…), exact method first,
    // then Cyclos's any-method form; /locate only as a last resort.
    final locators = [
      for (final c in type.candidates(v)) '${type.key}:$c',
      for (final c in type.candidates(v)) '*:$c',
    ];
    for (final l in locators) {
      final u = await asPayee(l);
      if (u != null) return (user: u, locator: l);
    }
    for (final l in locators) {
      final u = await located(l);
      if (u != null) return (user: u, locator: l);
    }
    throw ApiException(
        'No member found with this ${type.name.toLowerCase()}. Check it and try again.');
  }


  // 2–3. payee, then the types towards them
  Future<void> _choosePayee(CyclosUser user, String locator) async {
    setState(() {
      _payee = user;
      _payeeLocator = locator;
      _allTypes = const [];
      _type = null;
      _rules = null;
      _preview = null;
    });
    await _run(() async {
      final d = await _api.paymentData(to: locator);
      if (!mounted) return;
      setState(() {
        if (d.payee != null) _payee = d.payee;
        _allTypes = d.paymentTypes;
      });
      await _pickFirstType();
    });
  }

  List<PaymentType> get _types {
    final from = _from;
    if (from == null) return _allTypes;
    final f = _allTypes.where((t) => t.fromId == null || t.fromId == from.typeKey).toList();
    return f;
  }

  Future<void> _pickFirstType() async {
    final types = _types;
    if (types.isEmpty) {
      setState(() {
        _type = null;
        _rules = null;
      });
      if (_toSelf) {
        throw ApiException(
            'No transfer to your other accounts is enabled from this account. Choose another account.');
      }
      if (_payee != null && _allTypes.isNotEmpty) {
        throw ApiException('This account cannot pay this member. Choose another account.');
      }
      if (_payee != null) {
        throw ApiException('You have no payment type that can pay this member.');
      }
      return;
    }
    final keep = types.where((t) => t.id == _type?.id).firstOrNull;
    await _chooseType(keep ?? types.first);
  }

  // 4. rules of the type
  Future<void> _chooseType(PaymentType t) async {
    setState(() {
      _type = t;
      _rules = null;
      _preview = null;
    });
    final d = await _api.paymentData(to: _payeeLocator, type: t.id);
    if (!mounted) return;
    setState(() {
      _rules = d.rules ?? PaymentTypeRules();
      final fixed = _rules!.fixedAmount;
      if (fixed != null && fixed > 0) _amount.text = fixed.round().toString();
      if (!_allowed(_when)) _when = _When.now;
    });
  }

  bool _allowed(_When w) {
    final r = _rules ?? PaymentTypeRules();
    return switch (w) {
      _When.now => true,
      _When.onDate => r.maxInstallments >= 1,
      _When.installments => r.maxInstallments > 1,
      _When.recurring => r.allowsRecurring,
    };
  }

  PaymentTiming get _timing {
    final date = _date ?? DateTime.now().add(const Duration(days: 1));
    return switch (_when) {
      _When.now => const PayNow(),
      _When.onDate => PayScheduled(date),
      _When.installments =>
        PayScheduled(date, count: int.tryParse(_count.text) ?? 2),
      _When.recurring => PayRecurring(
          firstDate: _date ?? DateTime.now(),
          every: int.tryParse(_every.text) ?? 1,
          unit: _unit,
          occurrences: _untilCancelled ? null : int.tryParse(_occurrences.text),
        ),
    };
  }

  // 5. preview → confirm → perform
  Future<void> _review() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final p = await _api.previewPayment({
        'subject': _payeeLocator,
        'type': _type!.id,
        'amount': Money.fromInput(_amount.text).toString(),
        if (_note.text.trim().isNotEmpty) 'description': _note.text.trim(),
        ..._timing.toJson(),
      });
      if (!mounted) return;
      setState(() => _preview = p);
      if (p.skipConfirmation) await _perform();
    });
  }

  Future<void> _confirm() async {
    final p = _preview!;
    String? credential;
    if (p.requiresConfirmation) {
      credential = await askConfirmationPassword(
        context,
        title: S.read(ref).t('txPin'),
        input: p.confirmation,
        onSendOtp: (m) => _api.sendOtp(medium: m),
      );
      if (credential == null || credential.isEmpty || !mounted) return;
    }
    await _run(() => _perform(credential));
  }

  Future<void> _perform([String? credential]) async {
    final s = S.read(ref);
    final p = _preview!;
    final tx = await _api.performPayment(
      p.payment.isNotEmpty
          ? p.payment
          : {
              'subject': _payeeLocator,
              'type': _type!.id,
              'amount': p.amount.toString(),
              ..._timing.toJson(),
            },
      confirmationPassword: credential,
    );
    if (!mounted) return;
    ref.invalidate(accountsProvider);
    final immediate = _when == _When.now;
    final showReceipt = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.credit, size: 48),
        title: Text(immediate ? s.t('success') : 'Payment scheduled'),
        content: Text('${Money.xaf(p.amount)} to $_recipient\nReference: $tx'),
        actions: [
          if (immediate)
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('View receipt')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('done'))),
        ],
      ),
    );
    if (!mounted) return;
    if (showReceipt == true) {
      context.pushReplacement(
          '/transfer-details/${Uri.encodeComponent(CyclosApi.escapeNumeric(tx))}');
    } else {
      context.pop();
    }
  }

  /// Who/where the money goes, for the review and the success message.
  String get _recipient => _toSelf
      ? 'your ${_type?.toName ?? 'other account'}'
      : (_preview?.recipient.isNotEmpty == true ? _preview!.recipient : _payee?.display ?? '');

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: _when == _When.recurring ? now : now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 366 * 2)),
    );
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    final p = _preview;
    final locked = p != null || _busy;
    final rules = _rules;
    final descriptionMode = rules?.descriptionAvailability ?? 'optional';

    return Scaffold(
      appBar: AppBar(title: Text(s.t('sendMoney'))),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // 1. From account
                    if (_accounts.isNotEmpty)
                      DropdownButtonFormField<Account>(
                        initialValue: _from,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'From account'),
                        items: [
                          for (final a in _accounts)
                            DropdownMenuItem(
                              value: a,
                              child: Text(
                                  '${a.typeName}  ·  ${Money.xaf(a.available)}',
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: locked
                            ? null
                            : (a) {
                                setState(() => _from = a);
                                if (_payee != null || _toSelf) _run(_pickFirstType);
                              },
                      ),
                    const SizedBox(height: 16),

                    // Mode: to a member / between my accounts (if Cyclos enables it)
                    if (_selfTypes.isNotEmpty && widget.args?.payee == null) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                              value: false, icon: Icon(Icons.person_outline), label: Text('To a member')),
                          ButtonSegment(
                              value: true,
                              icon: Icon(Icons.swap_horiz),
                              label: Text('My accounts')),
                        ],
                        selected: {_toSelf},
                        onSelectionChanged: locked ? null : (v) => _setMode(v.first),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 2. Payee (or, between own accounts, the destination account)
                    if (_toSelf)
                      DropdownButtonFormField<PaymentType>(
                        key: ValueKey('self-${_from?.id}'),
                        initialValue: _types.contains(_type) ? _type : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'To account'),
                        items: [
                          for (final t in _types)
                            DropdownMenuItem(
                              value: t,
                              child: Text(
                                  t.toName == null ? t.name : '${t.toName}  ·  ${t.name}',
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: locked ? null : (t) => _run(() => _chooseType(t!)),
                      )
                    else if (_payee == null)
                      _PayeeSearch(
                        enabled: !locked,
                        principalTypes:
                            PrincipalTypeInput.withStandard(_start?.principalTypes ?? const []),
                        defaultPrincipalType: _start?.defaultPrincipalType,
                        onLocate: (type, value) => _run(() async {
                          final found = await _findPayee(type, value);
                          await _choosePayee(found.user, found.locator);
                        }),
                      )
                    else
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.goldLight,
                            foregroundColor: AppColors.greenDark,
                            child: Text(_payee!.initials),
                          ),
                          title: Text(_payee!.display,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(_payee!.subtitle ?? 'Payee'),
                          trailing: IconButton(
                            tooltip: 'Change payee',
                            icon: const Icon(Icons.close),
                            onPressed: locked
                                ? null
                                : () => setState(() {
                                      _payee = null;
                                      _payeeLocator = null;
                                      _allTypes = const [];
                                      _type = null;
                                      _rules = null;
                                    }),
                          ),
                        ),
                      ),

                    // 3. Payment type (between own accounts it is the "To account")
                    if (!_toSelf && _types.length > 1) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<PaymentType>(
                        key: ValueKey(_from?.id),
                        initialValue: _type,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Transfer type'),
                        items: [
                          for (final t in _types)
                            DropdownMenuItem(value: t, child: Text(t.name)),
                        ],
                        onChanged: locked ? null : (t) => _run(() => _chooseType(t!)),
                      ),
                    ] else if (!_toSelf && _type != null) ...[
                      const SizedBox(height: 8),
                      Text('Transfer type: ${_type!.name}',
                          style: const TextStyle(color: AppColors.muted)),
                    ],

                    // 4–5. Amount, description, timing
                    if (rules != null) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amount,
                        enabled: !locked && (rules.fixedAmount ?? 0) <= 0,
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
                          enabled: !locked,
                          maxLength: 100,
                          decoration: InputDecoration(
                              labelText: descriptionMode == 'required'
                                  ? 'Description'
                                  : s.t('note')),
                          validator: (v) => descriptionMode == 'required' &&
                                  (v == null || v.trim().isEmpty)
                              ? 'A description is required'
                              : null,
                        ),
                      ],
                      if (_When.values.where(_allowed).length > 1) ...[
                        const SizedBox(height: 8),
                        const Text('When', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final w in _When.values.where(_allowed))
                              ChoiceChip(
                                label: Text(switch (w) {
                                  _When.now => 'Now',
                                  _When.onDate => 'On a date',
                                  _When.installments => 'Instalments',
                                  _When.recurring => 'Recurring',
                                }),
                                selected: _when == w,
                                onSelected: locked ? null : (_) => setState(() => _when = w),
                              ),
                          ],
                        ),
                        if (_when != _When.now) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: locked ? null : _pickDate,
                            icon: const Icon(Icons.event),
                            label: Text(_date == null
                                ? (_when == _When.recurring ? 'Starting today' : 'Choose date')
                                : '${_when == _When.recurring ? 'Starting' : 'On'} ${DateFormat('d MMM y').format(_date!)}'),
                          ),
                        ],
                        if (_when == _When.installments) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _count,
                            enabled: !locked,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                                labelText: 'Number of monthly instalments (max ${rules.maxInstallments})'),
                            validator: (v) {
                              final n = int.tryParse(v ?? '') ?? 0;
                              return n < 2 || n > rules.maxInstallments
                                  ? 'Between 2 and ${rules.maxInstallments}'
                                  : null;
                            },
                          ),
                        ],
                        if (_when == _When.recurring) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            const Text('Every '),
                            SizedBox(
                              width: 56,
                              child: TextFormField(
                                controller: _every,
                                enabled: !locked,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _unit,
                              items: const [
                                DropdownMenuItem(value: 'days', child: Text('days')),
                                DropdownMenuItem(value: 'weeks', child: Text('weeks')),
                                DropdownMenuItem(value: 'months', child: Text('months')),
                              ],
                              onChanged: locked ? null : (u) => setState(() => _unit = u!),
                            ),
                          ]),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Until I cancel it'),
                            value: _untilCancelled,
                            onChanged: locked ? null : (v) => setState(() => _untilCancelled = v),
                          ),
                          if (!_untilCancelled)
                            TextFormField(
                              controller: _occurrences,
                              enabled: !locked,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(labelText: 'Number of payments'),
                              validator: (v) =>
                                  (int.tryParse(v ?? '') ?? 0) < 2 ? 'At least 2' : null,
                            ),
                        ],
                      ],
                    ],

                    // Review
                    if (p != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Column(children: [
                            SummaryRow('To', _toSelf ? (_type?.toName ?? 'My account') : p.recipient),
                            if (p.paymentTypeName != null) SummaryRow('Type', p.paymentTypeName!),
                            SummaryRow(s.t('amount'), Money.xaf(p.amount)),
                            SummaryRow(s.t('fee'), Money.xaf(p.fees)),
                            SummaryRow(s.t('total'), Money.xaf(p.totalAmount), strong: true),
                          ]),
                        ),
                      ),
                      if (p.confirmationMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(p.confirmationMessage!),
                      ],
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
                    if (rules != null)
                      FilledButton(
                        onPressed: _busy ? null : (p == null ? _review : _confirm),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Text(p == null ? 'Review' : '${s.t('confirm')} ${Money.xaf(p.amount)}'),
                      ),
                    if (p != null)
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _preview = null),
                        child: const Text('Change'),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Payee field with live suggestions, like the official user field:
/// type 2+ characters to search members; or type a phone / account
/// number / username and press "Use".
/// Payee step: the member types the payee's exact phone, e-mail or login
/// name. There is no search by name and no list of members (privacy).
class _PayeeSearch extends StatefulWidget {
  const _PayeeSearch({
    required this.enabled,
    required this.onLocate,
    required this.principalTypes,
    this.defaultPrincipalType,
  });
  final bool enabled;

  /// Finds the payee with the chosen identification method and value.
  final void Function(PrincipalTypeInput type, String value) onLocate;

  /// Phone, e-mail, login name (+ any other method Cyclos allows).
  final List<PrincipalTypeInput> principalTypes;
  final String? defaultPrincipalType;

  @override
  State<_PayeeSearch> createState() => _PayeeSearchState();
}

class _PayeeSearchState extends State<_PayeeSearch> {
  final _ctrl = TextEditingController();
  late PrincipalTypeInput _method = widget.principalTypes.firstWhere(
      (t) => t.key == widget.defaultPrincipalType,
      orElse: () => widget.principalTypes.first);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _select(PrincipalTypeInput m) => setState(() {
        _method = m;
        _ctrl.clear();
      });

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isNotEmpty) widget.onLocate(_method, v);
  }

  IconData _icon(PrincipalTypeInput t) => switch (t.kind) {
        'mobilePhone' => Icons.phone_iphone,
        'email' => Icons.alternate_email,
        'username' => Icons.person_outline,
        'accountNumber' => Icons.numbers,
        _ => Icons.badge_outlined,
      };

  TextInputType _keyboard(PrincipalTypeInput t) => switch (t.kind) {
        'mobilePhone' => TextInputType.phone,
        'email' => TextInputType.emailAddress,
        'accountNumber' => TextInputType.number,
        _ => TextInputType.text,
      };

  @override
  Widget build(BuildContext context) {
    final m = _method;
    final types = widget.principalTypes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (types.length > 1) ...[
          const Text('Send to', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in types)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(_icon(t), size: 18),
                    label: Text(t.name),
                    selected: m.key == t.key,
                    onSelected: widget.enabled ? (_) => _select(t) : null,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _ctrl,
          enabled: widget.enabled,
          autofocus: true,
          keyboardType: _keyboard(m),
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: "Recipient's ${m.name.toLowerCase()}",
            hintText: m.example ?? m.mask,
            prefixIcon: Icon(_icon(m)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.enabled && _ctrl.text.trim().isNotEmpty ? _submit : null,
          icon: const Icon(Icons.person_search),
          label: const Text('Find recipient'),
        ),
      ],
    );
  }
}
