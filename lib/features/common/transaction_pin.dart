import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../data/middleware/hub_api.dart';

/// True once the platform says the member has a transaction PIN, so the check
/// is made once per session.
final _txPinSetProvider = StateProvider<bool>((_) => false);

const _weakPins = {
  '000000', '111111', '222222', '333333', '444444', '555555',
  '666666', '777777', '888888', '999999', '123456', '654321', '123123', '112233',
};

/// Makes sure the member has created their 6-digit transaction PIN on the
/// platform before a money operation. Returns false if they cancelled.
Future<bool> ensureTransactionPin(BuildContext context, WidgetRef ref) async {
  if (ref.read(_txPinSetProvider)) return true;
  final hub = ref.read(hubApiProvider);
  try {
    if (await hub.pinIsSet()) {
      ref.read(_txPinSetProvider.notifier).state = true;
      return true;
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
  if (!context.mounted) return false;
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _CreatePinSheet(),
  );
  if (created == true) ref.read(_txPinSetProvider.notifier).state = true;
  return created == true;
}

/// Call when the platform answers PIN_NOT_SET (e.g. the PIN was reset at the
/// branch): the next operation asks the member to create it again.
void forgetTransactionPinState(WidgetRef ref) =>
    ref.read(_txPinSetProvider.notifier).state = false;

class _CreatePinSheet extends ConsumerStatefulWidget {
  const _CreatePinSheet();
  @override
  ConsumerState<_CreatePinSheet> createState() => _CreatePinSheetState();
}

class _CreatePinSheetState extends ConsumerState<_CreatePinSheet> {
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.read(ref);
    final pin = _pin.text.trim();
    if (pin.length != 6) {
      setState(() => _error = s.t('createTxPinHelp'));
      return;
    }
    if (_weakPins.contains(pin)) {
      setState(() => _error = s.t('createTxPinHelp'));
      return;
    }
    if (pin != _repeat.text.trim()) {
      setState(() => _error = s.t('pinsDiffer'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(hubApiProvider).setPin(pin);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      // Already set on another device: nothing to create.
      if (e.code == 'PIN_ALREADY_SET') {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    InputDecoration deco(String label) => InputDecoration(labelText: label, counterText: '');
    final field = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.t('createTxPin'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(s.t('createTxPinHelp')),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: field,
            autofocus: true,
            decoration: deco(s.t('txPin')),
          ),
          TextField(
            controller: _repeat,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: field,
            decoration: deco(s.t('repeatTxPin')),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(s.t('continue')),
          ),
        ],
      ),
    );
  }
}
