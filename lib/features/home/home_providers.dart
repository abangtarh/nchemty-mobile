import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/storage/secure_store.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';

final accountsProvider = FutureProvider.autoDispose<List<Account>>(
    (ref) => ref.watch(cyclosApiProvider).accounts());

/// The account id the member picked on Home (remembered on the phone).
class SelectedAccountId extends Notifier<String?> {
  @override
  String? build() {
    Future.microtask(() async {
      final saved = await ref.read(secureStoreProvider).readSelectedAccount();
      if (saved != null && state == null) state = saved;
    });
    return null;
  }

  Future<void> select(String id) async {
    state = id;
    await ref.read(secureStoreProvider).writeSelectedAccount(id);
  }
}

final selectedAccountIdProvider =
    NotifierProvider<SelectedAccountId, String?>(SelectedAccountId.new);

/// The account shown at the top of Home: the member's choice, else the
/// configured main account type, else the first account.
final mainAccountProvider = FutureProvider.autoDispose<Account?>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  if (accounts.isEmpty) return null;
  final chosen = ref.watch(selectedAccountIdProvider);
  for (final a in accounts) {
    if (a.id == chosen) return a;
  }
  return accounts.firstWhere(
    (a) => a.typeId == Env.mainAccountType,
    orElse: () => accounts.first,
  );
});

final recentActivityProvider =
    FutureProvider.autoDispose<List<HistoryEntry>>((ref) async {
  final main = await ref.watch(mainAccountProvider.future);
  if (main == null) return const [];
  final page =
      await ref.watch(cyclosApiProvider).history(main.typeId, pageSize: 5);
  return page.items;
});
