import 'package:flutter/material.dart';
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
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: strong ? AppColors.ink : AppColors.muted,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w400)),
          Flexible(
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

/// Asks for the Cyclos confirmation password (transaction PIN / OTP).
Future<String?> askConfirmationPassword(BuildContext context,
    {String title = 'Transaction PIN'}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ConfirmationSheet(title: title),
  );
}

/// Owns its controller so it is disposed with the sheet's widget tree, not
/// when the route's future completes (the TextField is still mounted during
/// the closing animation, so disposing earlier throws "used after disposed").
class _ConfirmationSheet extends StatefulWidget {
  const _ConfirmationSheet({required this.title});
  final String title;

  @override
  State<_ConfirmationSheet> createState() => _ConfirmationSheetState();
}

class _ConfirmationSheetState extends State<_ConfirmationSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN or code'),
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
