import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/cyclos/cyclos_operations_api.dart';
import '../common/rich_content.dart';
import '../common/widgets.dart';
import '../home/home_providers.dart';

class OperationArgs {
  const OperationArgs(this.op, {this.scope = 'user', this.title, this.params = const {}});
  final String op; // internal name or id
  final String scope;
  final String? title;
  final Map<String, String> params;
}

/// Runs one Cyclos custom operation like the official app:
/// form (data-for-run) → run → result. A result may carry actions (e.g. the
/// "Confirm" of a MoMo preview), which run as internal operations with the
/// parameters Cyclos returned; the transaction code is asked whenever the
/// operation requires a confirmation password.
class OperationScreen extends ConsumerStatefulWidget {
  const OperationScreen({super.key, required this.args});
  final OperationArgs args;

  @override
  ConsumerState<OperationScreen> createState() => _OperationScreenState();
}

class _OperationScreenState extends ConsumerState<OperationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _choices = <String, String?>{};

  bool _loading = true;
  bool _busy = false;
  ApiException? _error;
  OperationForm? _form;
  OperationResult? _result;
  bool _finished = false;

  CyclosOperationsApi get _api => ref.read(cyclosOperationsApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
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

  Future<void> _load() => _guard(() async {
        final f = await _api.dataForRun(widget.args.op, scope: widget.args.scope);
        if (!mounted) return;
        for (final field in f.fields) {
          final initial = widget.args.params[field.key] ?? field.defaultValue;
          if (field.options.isNotEmpty || field.type == 'boolean') {
            _choices[field.key] = initial;
          } else {
            _controllers[field.key] = TextEditingController(text: initial ?? '');
          }
        }
        setState(() => _form = f);
      });

  Map<String, String> get _values => {
        ...widget.args.params,
        for (final e in _controllers.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        for (final e in _choices.entries)
          if (e.value != null) e.key: e.value!,
      };

  /// Confirmation text and/or transaction code, as the operation requires.
  Future<(bool, String?)> _confirm(OperationDef def, {OperationForm? form}) async {
    final text = form?.def.confirmationText ?? def.confirmationText;
    final needsCode = form?.def.requireConfirmationPassword ?? def.requireConfirmationPassword;
    if (needsCode) {
      var input = form?.confirmation;
      if (input == null) {
        final data = await _api.dataForRun(def.id, scope: def.scope);
        input = data.confirmation;
      }
      if (!mounted) return (false, null);
      if (input != null) {
        final code = await askConfirmationPassword(
          context,
          title: text ?? 'Transaction code',
          input: input,
          onSendOtp: (m) => ref.read(cyclosApiProvider).sendOtp(medium: m),
        );
        if (code == null || code.isEmpty) return (false, null);
        return (true, code);
      }
    }
    if (text != null && text.isNotEmpty) {
      if (!mounted) return (false, null);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(def.name),
          content: Text(htmlToText(text)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
          ],
        ),
      );
      return (ok == true, null);
    }
    return (true, null);
  }

  Future<void> _submit() async {
    final form = _form!;
    if (!_formKey.currentState!.validate()) return;
    final (go, code) = await _confirm(form.def, form: form);
    if (!go || !mounted) return;
    await _guard(() async {
      final r = await _api.run(form.def.key,
          scope: widget.args.scope, formParameters: _values, confirmationPassword: code);
      await _handle(r);
    });
  }

  Future<void> _runAction(OperationAction a) async {
    final (go, code) = await _confirm(a.op);
    if (!go || !mounted) return;
    await _guard(() async {
      final r = await _api.run(a.op.id,
          scope: a.op.scope, formParameters: a.parameters, confirmationPassword: code);
      await _handle(r);
    });
  }

  Future<void> _handle(OperationResult r) async {
    if (!mounted) return;
    ref.invalidate(accountsProvider);
    setState(() {
      _result = r;
      _finished = r.actions.isEmpty && r.resultType != 'resultPage';
    });
    final auto = r.autoRunActionId;
    if (auto != null) {
      final a = r.actions.where((x) => x.op.id == auto).firstOrNull;
      if (a != null) await _runAction(a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _form;
    return Scaffold(
      appBar: AppBar(title: Text(widget.args.title ?? f?.def.name ?? 'Service')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_result != null ? _buildResult(context, _result!) : _buildForm(context, f)),
      ),
    );
  }

  Widget _errorBox(BuildContext context) => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                _error!.isWrongConfirmation
                    ? 'Wrong transaction code. Please try again.'
                    : _error!.message,
                style: const TextStyle(color: AppColors.debit)),
            if (_error!.details != null)
              TextButton(
                  onPressed: () => showApiError(context, _error!), child: const Text('Details')),
          ]),
        );

  Widget _buildForm(BuildContext context, OperationForm? f) {
    if (f == null) {
      return ListView(padding: const EdgeInsets.all(20), children: [_errorBox(context)]);
    }
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (f.informationText?.isNotEmpty == true) ...[
            Text(htmlToText(f.informationText!), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
          ],
          for (final field in f.fields) ...[
            _field(field),
            const SizedBox(height: 16),
          ],
          _errorBox(context),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(f.submitLabel ?? 'Continue'),
          ),
        ],
      ),
    );
  }

  Widget _field(OperationField field) {
    final label = field.required ? field.name : '${field.name} (optional)';
    String? need(String? v) =>
        field.required && (v == null || v.trim().isEmpty) ? 'Required' : null;

    if (field.type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.name),
        subtitle: field.informationText == null ? null : Text(field.informationText!),
        value: _choices[field.key] == 'true',
        onChanged: _busy ? null : (v) => setState(() => _choices[field.key] = '$v'),
      );
    }
    if (field.options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue: field.options.any((o) => o.$1 == _choices[field.key])
            ? _choices[field.key]
            : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, helperText: field.informationText),
        items: [
          for (final o in field.options) DropdownMenuItem(value: o.$1, child: Text(o.$2)),
        ],
        validator: need,
        onChanged: _busy ? null : (v) => setState(() => _choices[field.key] = v),
      );
    }
    final numeric = field.type == 'integer' || field.type == 'decimal';
    return TextFormField(
      controller: _controllers[field.key],
      enabled: !_busy,
      maxLines: field.type == 'text' ? 4 : 1,
      keyboardType: field.looksLikePhone
          ? TextInputType.phone
          : numeric
              ? TextInputType.numberWithOptions(decimal: field.type == 'decimal')
              : TextInputType.text,
      inputFormatters: [
        if (field.type == 'integer') FilteringTextInputFormatter.digitsOnly,
        if (field.type == 'decimal') FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: numeric ? const TextStyle(fontSize: 22, fontWeight: FontWeight.w800) : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: field.informationText,
        prefixText: field.looksLikePhone ? '+237 ' : null,
      ),
      validator: need,
    );
  }

  Widget _buildResult(BuildContext context, OperationResult r) {
    // Only a notification carries an explicit outcome. Text results are the
    // script's own message (a preview, or a refusal such as "not open for
    // your account"), so they are shown neutrally, never as a success.
    final isNotification = r.resultType == 'notification' || (r.content == null && r.notification != null);
    final failed = r.isError || r.notificationLevel == 'warning';
    final body = r.content ?? r.notification;
    final blocks = body == null || body.isEmpty
        ? const <RichBlock>[]
        : (r.resultType == 'plainText'
            ? [for (final l in body.split('\n')) if (l.trim().isNotEmpty) RichParagraph(l.trim())]
            : parseRichContent(body));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (isNotification && _finished)
          Center(
            child: Icon(
              failed ? Icons.error_outline : Icons.check_circle,
              size: 64,
              color: failed ? AppColors.debit : AppColors.credit,
            ),
          ),
        if (r.title?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text(r.title!,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
        if (blocks.isNotEmpty) ...[
          const SizedBox(height: 12),
          RichContentView(blocks: blocks),
        ],
        if (r.url != null) ...[
          const SizedBox(height: 12),
          SelectableText(r.url!),
        ],
        if (r.resultType == 'resultPage')
          for (final row in r.rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [
                  for (final c in r.columns)
                    if (_cell(row[c.$1]).isNotEmpty) SummaryRow(c.$2, _cell(row[c.$1])),
                ]),
              ),
            ),
        _errorBox(context),
        const SizedBox(height: 20),
        for (final a in r.actions) ...[
          a.primary || r.actions.length == 1
              ? FilledButton(
                  onPressed: _busy ? null : () => _runAction(a),
                  child: Text(a.op.label ?? a.op.name),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : () => _runAction(a),
                  child: Text(a.op.label ?? a.op.name),
                ),
          const SizedBox(height: 8),
        ],
        if (r.actions.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : () => context.pop(),
            child: const Text('Cancel'),
          )
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => setState(() {
                  _result = null;
                  _finished = false;
                }),
                child: const Text('Start again'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Close'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Check recent activity on Home'),
          ),
      ],
    );
  }
}

/// A result-page cell: entity references show their name, not the raw map.
String _cell(Object? v) => switch (v) {
      null => '',
      Map() => '${v['display'] ?? v['name'] ?? v['label'] ?? ''}',
      List() => v.map(_cell).where((e) => e.isNotEmpty).join(', '),
      _ => htmlToText('$v'),
    };

/// All custom operations the member can run (loans, savings, MoMo, …).
final operationsListProvider = FutureProvider.autoDispose<List<OperationDef>>(
    (ref) => ref.watch(cyclosOperationsApiProvider).list());

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      body: ops.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: ErrorRetry(error: e, onRetry: () => ref.invalidate(operationsListProvider))),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No services available'))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final op = list[i];
                  return Card(
                    child: ListTile(
                      title: Text(op.label ?? op.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/op',
                          extra: OperationArgs(op.key, scope: op.scope, title: op.label ?? op.name)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
