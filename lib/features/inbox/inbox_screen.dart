import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/cyclos/cyclos_inbox_api.dart';
import '../../data/models/models.dart';
import '../common/widgets.dart';

/// Inbox: payment requests to accept or reject, and Cyclos notifications.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(ref);
    final badge = ref.watch(inboxBadgeProvider).valueOrNull;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('inbox')),
          bottom: TabBar(tabs: [
            Tab(text: '${s.t('requestsTab')}${(badge?.requests ?? 0) > 0 ? ' (${badge!.requests})' : ''}'),
            Tab(text: '${s.t('notificationsTab')}${(badge?.unread ?? 0) > 0 ? ' (${badge!.unread})' : ''}'),
          ]),
        ),
        body: const TabBarView(children: [_RequestsTab(), _NotificationsTab()]),
      ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(incomingRequestsProvider);
    final df = DateFormat('d MMM y');
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(incomingRequestsProvider);
        ref.invalidate(inboxBadgeProvider);
        await ref.read(incomingRequestsProvider.future);
      },
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: ErrorRetry(error: e, onRetry: () => ref.invalidate(incomingRequestsProvider)),
          ),
        ]),
        data: (items) => items.isEmpty
            ? ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('No payment requests waiting for you.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              ])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = items[i];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.goldLight,
                        foregroundColor: AppColors.greenDark,
                        child: Icon(Icons.request_quote_outlined),
                      ),
                      title: Text(r.from, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if (r.description?.isNotEmpty == true) r.description!,
                        if (r.expires != null) 'Expires ${df.format(r.expires!)}',
                      ].join('\n')),
                      isThreeLine: r.description?.isNotEmpty == true && r.expires != null,
                      trailing: Text(Money.xaf(r.amount),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () => context.push('/payment-request/${Uri.encodeComponent(r.id)}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

final _notificationsProvider = FutureProvider.autoDispose<List<InboxNotification>>(
    (ref) async => (await ref.watch(cyclosInboxApiProvider).notifications()).items);

class _NotificationsTab extends ConsumerWidget {
  const _NotificationsTab();

  Future<void> _open(BuildContext context, WidgetRef ref, InboxNotification n) async {
    if (!n.read) {
      n.read = true;
      ref.read(cyclosInboxApiProvider).markRead([n.id]).catchError((_) {});
      ref.invalidate(inboxBadgeProvider);
    }
    final id = n.entityId;
    if (id == null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(n.subject),
          content: Text(n.message),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    } else if (n.isPaymentRequest) {
      await context.push('/payment-request/${Uri.encodeComponent(id)}');
    } else if (n.entityType == 'transfer' || n.entityType == 'transaction') {
      await context.push('/transfer-details/${Uri.encodeComponent(id)}');
    } else {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(n.subject),
          content: Text(n.message),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    }
    ref.invalidate(_notificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_notificationsProvider);
    final df = DateFormat('d MMM, HH:mm');
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_notificationsProvider);
        ref.invalidate(inboxBadgeProvider);
        await ref.read(_notificationsProvider.future);
      },
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: ErrorRetry(error: e, onRetry: () => ref.invalidate(_notificationsProvider)),
          ),
        ]),
        data: (items) => items.isEmpty
            ? ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('No notifications yet.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              ])
            : ListView(
                children: [
                  if (items.any((n) => !n.read))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          await ref
                              .read(cyclosInboxApiProvider)
                              .markRead([for (final n in items) if (!n.read) n.id])
                              .catchError((_) {});
                          ref.invalidate(_notificationsProvider);
                          ref.invalidate(inboxBadgeProvider);
                        },
                        child: const Text('Mark all as read'),
                      ),
                    ),
                  for (final n in items)
                    ListTile(
                      leading: Icon(
                        n.isPaymentRequest
                            ? Icons.request_quote_outlined
                            : n.type?.contains('Received') == true
                                ? Icons.south_west
                                : Icons.notifications_outlined,
                        color: n.read ? AppColors.muted : AppColors.green,
                      ),
                      title: Text(n.subject,
                          style: TextStyle(
                              fontWeight: n.read ? FontWeight.w400 : FontWeight.w700)),
                      subtitle: Text(n.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Text(df.format(n.date),
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      onTap: () => _open(context, ref, n),
                    ),
                ],
              ),
      ),
    );
  }
}

/// One payment request: what paying it costs, then Pay or Decline.
class PaymentRequestScreen extends ConsumerStatefulWidget {
  const PaymentRequestScreen({super.key, required this.requestKey});
  final String requestKey;

  @override
  ConsumerState<PaymentRequestScreen> createState() => _PaymentRequestScreenState();
}

class _PaymentRequestScreenState extends ConsumerState<PaymentRequestScreen> {
  late Future<PaymentRequestPreview> _preview =
      ref.read(cyclosInboxApiProvider).previewRequest(widget.requestKey);
  bool _busy = false;

  Future<String?> _credential(PaymentPreview p) async {
    if (!p.requiresConfirmation) return '';
    return askConfirmationPassword(
      context,
      title: S.read(ref).t('txPin'),
      input: p.confirmation,
      onSendOtp: (m) => ref.read(cyclosApiProvider).sendOtp(medium: m),
    );
  }

  void _done() {
    ref.invalidate(incomingRequestsProvider);
    ref.invalidate(inboxBadgeProvider);
  }

  Future<void> _pay(PaymentRequestPreview r) async {
    final cred = await _credential(r.payment);
    if (cred == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final key = await ref.read(cyclosInboxApiProvider).acceptRequest(widget.requestKey,
          confirmationPassword: cred.isEmpty ? null : cred);
      _done();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.credit, size: 40),
          title: const Text('Request paid'),
          content: Text(key == null
              ? 'The payment to ${r.from} is scheduled.'
              : '${Money.xaf(r.payment.totalAmount)} paid to ${r.from}.'),
          actions: [
            if (key != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  context.pushReplacement(
                      '/transfer-details/${Uri.encodeComponent(RegExp(r'^\d+$').hasMatch(key) ? "'$key" : key)}');
                },
                child: const Text('View receipt'),
              ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ],
        ),
      );
      if (mounted && context.canPop()) context.pop();
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(PaymentRequestPreview r) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Decline this request?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${r.from} will be told you declined ${Money.xaf(r.payment.amount)}.'),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Decline')),
        ],
      ),
    );
    final comments = reason.text.trim();
    reason.dispose();
    if (ok != true || !mounted) return;
    final cred = await _credential(r.payment);
    if (cred == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(cyclosInboxApiProvider).rejectRequest(widget.requestKey,
          confirmationPassword: cred.isEmpty ? null : cred, comments: comments);
      _done();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Request declined')));
      if (context.canPop()) context.pop();
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM y');
    return Scaffold(
      appBar: AppBar(title: const Text('Payment request')),
      body: FutureBuilder<PaymentRequestPreview>(
        future: _preview,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: ErrorRetry(
                error: snap.error!,
                onRetry: () => setState(() => _preview =
                    ref.read(cyclosInboxApiProvider).previewRequest(widget.requestKey)),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final r = snap.data!;
          final p = r.payment;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Column(children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.goldLight,
                    foregroundColor: AppColors.greenDark,
                    child: Icon(Icons.request_quote_outlined),
                  ),
                  const SizedBox(height: 12),
                  Text('${r.from} requests',
                      style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(Money.xaf(p.amount),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(children: [
                    SummaryRow('From', r.from),
                    if (r.description?.isNotEmpty == true) SummaryRow('For', r.description!),
                    if (p.paymentTypeName != null) SummaryRow('Type', p.paymentTypeName!),
                    if (p.fees > 0) SummaryRow('Fees', Money.xaf(p.fees)),
                    SummaryRow('You pay', Money.xaf(p.totalAmount), strong: true),
                    if (r.expires != null) SummaryRow('Expires', df.format(r.expires!)),
                    if (r.transactionNumber != null) SummaryRow('Reference', r.transactionNumber!),
                  ]),
                ),
              ),
              if (p.confirmationMessage?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(p.confirmationMessage!, style: const TextStyle(color: AppColors.muted)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : () => _pay(r),
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text('Pay ${Money.xaf(p.totalAmount)}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : () => _decline(r),
                icon: const Icon(Icons.close),
                label: const Text('Decline'),
              ),
            ],
          );
        },
      ),
    );
  }
}
