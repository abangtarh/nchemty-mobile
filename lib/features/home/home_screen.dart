import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
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
                      if (v == 'kyc') context.push('/kyc');
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
                child: main.when(
                  data: (a) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(a?.typeName ?? '',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8))),
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
                    _Action(Icons.add, s.t('topUp'), () => context.push('/momo/topup')),
                    _Action(Icons.phone_iphone, s.t('cashOut'), () => context.push('/momo/cashout')),
                    _Action(Icons.account_balance_outlined, s.t('loans'), () => context.push('/products')),
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
                            onTap: () => context.push('/history/${a.typeId}'),
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
  const _BalanceCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
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
