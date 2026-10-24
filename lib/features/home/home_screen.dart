import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/cyclos/cyclos_operations_api.dart';
import '../../data/models/models.dart';
import '../auth/auth_controller.dart';
import '../common/widgets.dart';
import '../kyc/kyc_launcher.dart';
import '../operations/operation_screen.dart';
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
                      if (v == 'kyc') openKycWizard(context, s.t('verifyId'));
                      if (v == 'services') context.push('/services');
                      if (v == 'verify') context.push('/verify');
                      if (v == 'products') {
                        _hub(context, '/products', 'Loans and savings');
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
                      const PopupMenuItem(value: 'services', child: Text('Services')),
                      const PopupMenuItem(value: 'verify', child: Text('Verify a receipt')),
                      PopupMenuItem(value: 'products', child: Text(s.t('loansSavings'))),
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
                  final a = main.valueOrNull;
                  if (a != null) context.push('/history/${a.typeId}');
                },
                child: main.when(
                  data: (a) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: _AccountDropdown(
                              accounts: accounts.valueOrNull ?? const [],
                              selected: a,
                              onChanged: (acc) => ref
                                  .read(selectedAccountIdProvider.notifier)
                                  .select(acc.id),
                            ),
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
                      Row(
                        children: [
                          Text(s.t('available'),
                              style: const TextStyle(color: AppColors.goldLight)),
                          const Spacer(),
                          Text('History',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w600)),
                          Icon(Icons.chevron_right,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ],
                      ),
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
                    _Action(Icons.south_west, 'Receive', () => context.push('/qr/receive')),
                    _Action(Icons.add, s.t('topUp'),
                        () => _openMomo(context, ref, topUp: true)),
                    _Action(Icons.phone_iphone, s.t('cashOut'),
                        () => _openMomo(context, ref, topUp: false)),
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
                    for (final a in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text(a.typeName,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(a.maskedNumber),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(Money.xaf(a.balance),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: a.balance < 0
                                            ? AppColors.debit
                                            : AppColors.ink)),
                                const Icon(Icons.chevron_right, color: AppColors.muted),
                              ],
                            ),
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

/// Top up / Cash out are Cyclos custom operations: use the configured
/// internal name, else the first operation whose name matches; if none is
/// found, show all services.
Future<void> _openMomo(BuildContext context, WidgetRef ref, {required bool topUp}) async {
  final configured = topUp ? Env.topupOperation : Env.cashoutOperation;
  String norm(String v) => v.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  final words = topUp ? ['topup', 'fund', 'deposit', 'recharge'] : ['cashout', 'withdraw', 'retrait'];
  try {
    final ops = await ref.read(cyclosOperationsApiProvider).list();
    OperationDef? match;
    for (final op in ops) {
      final names = [op.internalName ?? '', op.name, op.label ?? ''].map(norm).join(' ');
      if (configured.isNotEmpty
          ? (op.internalName == configured || op.id == configured)
          : words.any(names.contains)) {
        match = op;
        break;
      }
    }
    if (!context.mounted) return;
    if (match == null) {
      context.push('/services');
    } else {
      context.push('/op',
          extra: OperationArgs(match.key,
              scope: match.scope, title: topUp ? 'Top up from MoMo' : 'Cash out to MoMo'));
    }
  } on ApiException catch (e) {
    if (context.mounted) showApiError(context, e);
  }
}

/// Hub features open only when the hub is enabled for this build.
void _hub(BuildContext context, String route, String feature) {
  if (Env.hubEnabled) {
    context.push(route);
  } else {
    showComingSoon(context, feature);
  }
}

/// Account switcher on the balance card (white on green).
class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.accounts,
    required this.selected,
    required this.onChanged,
  });
  final List<Account> accounts;
  final Account? selected;
  final ValueChanged<Account> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600);
    if (accounts.length < 2 || selected == null) {
      return Text(selected?.typeName ?? '', style: style, overflow: TextOverflow.ellipsis);
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected!.id,
        isDense: true,
        isExpanded: true,
        dropdownColor: AppColors.greenDark,
        iconEnabledColor: Colors.white,
        style: style,
        items: [
          for (final a in accounts)
            DropdownMenuItem(
              value: a.id,
              child: Text('${a.typeName} · ${Money.xaf(a.available)}',
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        selectedItemBuilder: (_) => [
          for (final a in accounts)
            Text(a.typeName, style: style, overflow: TextOverflow.ellipsis),
        ],
        onChanged: (id) {
          final acc = accounts.where((a) => a.id == id).firstOrNull;
          if (acc != null) onChanged(acc);
        },
      ),
    );
  }
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
