import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/models.dart';
import '../auth/auth_controller.dart';
import '../common/widgets.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(ref);
    final user = ref.watch(authProvider.select((a) => a.user));
    final accounts = ref.watch(accountsProvider);
    final main = ref.watch(mainAccountProvider);
    final recent = ref.watch(recentActivityProvider);

    Future<void> refresh() async {
      ref.invalidate(accountsProvider);
      await ref.read(recentActivityProvider.future);
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(user?.shortDisplay ?? user?.display ?? '',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Menu',
                    onSelected: (v) {
                      if (v == 'kyc') {
                        Env.hubEnabled
                            ? context.push('/kyc')
                            : showComingSoon(context, s.t('verifyId'));
                      }
                      if (v == 'logout') ref.read(authProvider.notifier).logout();
                      if (v == 'lang') {
                        final isEn = ref.read(localeProvider).languageCode == 'en';
                        ref
                            .read(localeProvider.notifier)
                            .set(Locale(isEn ? 'fr' : 'en'));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'kyc', child: Text(s.t('verifyId'))),
                      const PopupMenuItem(value: 'lang', child: Text('English / Français')),
                      PopupMenuItem(value: 'logout', child: Text(s.t('logout'))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _BalanceCard(
                onTap: () {
                  final list = accounts.valueOrNull;
                  if (list != null && list.length > 1) {
                    _pickAccount(context, ref, list, main.valueOrNull?.id);
                  }
                },
                child: main.when(
                  data: (a) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(a?.typeName ?? '',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8))),
                              if ((accounts.valueOrNull?.length ?? 0) > 1)
                                Icon(Icons.expand_more,
                                    size: 18,
                                    color: Colors.white.withValues(alpha: 0.8)),
                            ],
                          ),
                          Text(a?.maskedNumber ?? '',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(Money.xaf(a?.available),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(s.t('available'),
                          style: const TextStyle(color: AppColors.goldLight)),
                    ],
                  ),
                  loading: () => const SizedBox(
                      height: 88,
                      child: Center(
                          child: CircularProgressIndicator(color: Colors.white))),
                  error: (e, _) => ErrorRetry(
                      error: e, onRetry: () => ref.invalidate(accountsProvider)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final a in [
                    _Action(Icons.qr_code_scanner, 'Scan', () => context.push('/qr/scan'),
                        highlight: true),
                    _Action(Icons.north_east, s.t('send'), () => context.push('/transfer')),
                    _Action(Icons.add, s.t('topUp'),
                        () => _hub(context, '/momo/topup', 'MoMo top-up')),
                    _Action(Icons.phone_iphone, s.t('cashOut'),
                        () => _hub(context, '/momo/cashout', 'MoMo cash-out')),
                    _Action(Icons.account_balance_outlined, s.t('loans'),
                        () => _hub(context, '/products', 'Loans and savings')),
                  ])
                    Expanded(child: a),
                ],
              ),
              const SizedBox(height: 24),
              Text(s.t('accounts'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              accounts.when(
                data: (list) => Column(
                  children: [
                    for (final a in list
                        .where((x) => x.id != main.valueOrNull?.id))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text(a.typeName,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(a.maskedNumber),
                            trailing: Text(Money.xaf(a.balance),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: a.balance < 0
                                        ? AppColors.debit
                                        : AppColors.ink)),
                            onTap: () => ref
                                .read(selectedAccountIdProvider.notifier)
                                .select(a.id),
                            onLongPress: () => context.push('/history/${a.typeId}'),
                          ),
                        ),
                      ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s.t('recent'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  TextButton(
                    onPressed: () {
                      final type = main.valueOrNull?.typeId;
                      if (type != null) context.push('/history/$type');
                    },
                    child: Text(s.t('seeAll')),
                  ),
                ],
              ),
              recent.when(
                data: (items) => Column(
                    children: items.map((e) => HistoryTile(entry: e)).toList()),
                loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator())),
                error: (e, _) => ErrorRetry(
                    error: e,
                    onRetry: () => ref.invalidate(recentActivityProvider)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(22), child: child),
        ),
      );
}

/// Hub features open only when the hub is enabled for this build.
void _hub(BuildContext context, String route, String feature) {
  if (Env.hubEnabled) {
    context.push(route);
  } else {
    showComingSoon(context, feature);
  }
}

Future<void> _pickAccount(BuildContext context, WidgetRef ref,
    List<Account> accounts, String? currentId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Show account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final a in accounts)
            ListTile(
              leading: Icon(
                a.id == currentId ? Icons.radio_button_checked : Icons.radio_button_off,
                color: AppColors.green,
              ),
              title: Text(a.typeName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(a.maskedNumber),
              trailing: Text(Money.xaf(a.available),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: a.balance < 0 ? AppColors.debit : AppColors.ink)),
              onTap: () {
                ref.read(selectedAccountIdProvider.notifier).select(a.id);
                Navigator.pop(c);
              },
            ),
        ],
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap, {this.highlight = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: highlight ? AppColors.gold : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: highlight ? null : Border.all(color: AppColors.line),
              ),
              child: Icon(icon,
                  color: highlight ? AppColors.greenDark : AppColors.green),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
