import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';
import '../common/widgets.dart';

final _transferProvider = FutureProvider.autoDispose
    .family<TransferDetails, String>((ref, key) => ref.watch(cyclosApiProvider).transfer(key));

/// Receipt for one history entry (official: banking/transfer/:key →
/// GET /transfers/{key}).
class TransferDetailsScreen extends ConsumerWidget {
  const TransferDetailsScreen({super.key, required this.transferKey});
  final String transferKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_transferProvider(transferKey));
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction details')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorRetry(
              error: e, onRetry: () => ref.invalidate(_transferProvider(transferKey))),
        ),
        data: (t) => _Receipt(t: t),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.t});
  final TransferDetails t;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('d MMM y, HH:mm').format(t.date);
    final feeTotal = t.fees.fold<num>(0, (s, f) => s + f.$2);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Column(children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.goldLight,
              foregroundColor: AppColors.greenDark,
              child: Icon(Icons.receipt_long),
            ),
            const SizedBox(height: 12),
            Text(Money.xaf(t.amount),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(when, style: const TextStyle(color: AppColors.muted)),
            if (t.statuses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final st in t.statuses)
                    Chip(label: Text(st), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              SummaryRow('From', t.fromName),
              if (t.fromAccount != null) SummaryRow('From account', t.fromAccount!),
              SummaryRow('To', t.toName),
              if (t.toAccount != null) SummaryRow('To account', t.toAccount!),
              if (t.typeName != null) SummaryRow('Type', t.typeName!),
              if (t.description?.isNotEmpty == true) SummaryRow('Description', t.description!),
              if (t.channel != null) SummaryRow('Channel', t.channel!),
            ]),
          ),
        ),
        if (t.fees.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (final f in t.fees) SummaryRow(f.$1, Money.xaf(f.$2)),
                SummaryRow('Total fees', Money.xaf(feeTotal), strong: true),
              ]),
            ),
          ),
        ],
        if (t.transactionNumber != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Reference'),
              subtitle: SelectableText(t.transactionNumber!),
              trailing: IconButton(
                tooltip: 'Copy reference',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: t.transactionNumber!));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Reference copied')));
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
