import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/models.dart';

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiException
        ? (error as ApiException).message
        : 'Something went wrong.';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(msg, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
              if (error is ApiException && (error as ApiException).details != null)
                TextButton(
                  onPressed: () => showApiError(context, error),
                  child: const Text('Details'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('d MMM, HH:mm').format(entry.date);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push('/transfer-details/${Uri.encodeComponent(entry.key)}'),
      title: Text(entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        entry.description?.isNotEmpty == true ? '${entry.description} · $when' : when,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        Money.xaf(entry.amount, signed: true),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: entry.isCredit ? AppColors.credit : AppColors.ink,
        ),
      ),
    );
  }
}

/// Row in a summary card: "Fee ........ 74 XAF".
class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Both sides wrap, so long French labels or values never overflow.
          Expanded(
            flex: 5,
            child: Text(label,
                style: TextStyle(
                    color: strong ? AppColors.ink : AppColors.muted,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Asks for the confirmation credential Cyclos requires for this action.
///
/// [input] comes from the payment preview (`confirmationPasswordInput`).
/// When it is null the caller should not ask at all. When Cyclos only
/// accepts device / PIN / authenticator confirmation, this explains that
/// and returns null.
Future<String?> askConfirmationPassword(
  BuildContext context, {
  String title = 'Transaction PIN',
  ConfirmationInput? input,
  Future<void> Function(String medium)? onSendOtp,
}) async {
  if (input != null && !input.usable) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmation not supported yet'),
        content: const Text(
            'Cyclos asks for this payment to be confirmed on a trusted device or with an authenticator app. This app version can only confirm with a password, PIN or SMS code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ConfirmationSheet(
      title: input?.label ?? title,
      numeric: input?.numeric ?? true,
      otpMedium: (input?.isOtp ?? false)
          ? (input!.otpMediums.isNotEmpty ? input.otpMediums.first : 'sms')
          : null,
      onSendOtp: onSendOtp,
    ),
  );
}

/// Owns its controller so it is disposed with the sheet's widget tree, not
/// when the route's future completes (the TextField is still mounted during
/// the closing animation, so disposing earlier throws "used after disposed").
class _ConfirmationSheet extends StatefulWidget {
  const _ConfirmationSheet({
    required this.title,
    required this.numeric,
    this.otpMedium,
    this.onSendOtp,
  });
  final String title;
  final bool numeric;
  final String? otpMedium;
  final Future<void> Function(String medium)? onSendOtp;

  @override
  State<_ConfirmationSheet> createState() => _ConfirmationSheetState();
}

class _ConfirmationSheetState extends State<_ConfirmationSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _info;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final medium = widget.otpMedium;
    final send = widget.onSendOtp;
    if (medium == null || send == null) return;
    setState(() {
      _sending = true;
      _info = null;
    });
    try {
      await send(medium);
      if (mounted) setState(() => _info = 'Code sent by ${medium.toUpperCase()}.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _info = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (widget.otpMedium != null) ...[
            OutlinedButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.sms_outlined),
              label: Text(_sending ? 'Sending…' : 'Send me a code'),
            ),
            if (_info != null) ...[
              const SizedBox(height: 8),
              Text(_info!),
            ],
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctrl,
            autofocus: widget.otpMedium == null,
            obscureText: true,
            keyboardType:
                widget.numeric ? TextInputType.number : TextInputType.visiblePassword,
            decoration: InputDecoration(labelText: widget.title),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

/// Error dialog that shows Cyclos's message and, on request, the technical
/// details (request, status, body) with a copy button for support.
Future<void> showApiError(BuildContext context, Object error,
    {String title = 'Something went wrong'}) {
  final e = error is ApiException ? error : null;
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e?.message ?? error.toString()),
            if (e?.code != null) ...[
              const SizedBox(height: 8),
              Text('Code: ${e!.code}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
            if (e?.details != null)
              Theme(
                data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Details', style: TextStyle(fontSize: 14)),
                  children: [
                    SelectableText(e!.details!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (e?.details != null)
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: '${e!.message}\ncode: ${e.code}\n${e.details}'));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Details copied')));
            },
            child: const Text('Copy details'),
          ),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
      ],
    ),
  );
}

/// Placeholder for features that need hub routes not deployed yet.
Future<void> showComingSoon(BuildContext context, String feature) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$feature is coming soon'),
        content: const Text(
            'This feature is being connected to Nchemty\'s systems and will be available in a coming update.'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
