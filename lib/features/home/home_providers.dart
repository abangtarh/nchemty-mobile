import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';

final accountsProvider = FutureProvider.autoDispose<List<Account>>(
    (ref) => ref.watch(cyclosApiProvider).accounts());

/// The member's main (current) account, falling back to the first one.
final mainAccountProvider = FutureProvider.autoDispose<Account?>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  if (accounts.isEmpty) return null;
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
