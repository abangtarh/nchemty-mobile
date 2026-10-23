import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';
import '../common/widgets.dart';

/// Paged account history for one account type.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, required this.accountType});
  final String accountType;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _items = <HistoryEntry>[];
  final _scroll = ScrollController();
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!_hasNext && !reset)) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 0;
        _hasNext = true;
        _items.clear();
      }
    });
    try {
      final page = await ref
          .read(cyclosApiProvider)
          .history(widget.accountType, page: _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasNext = page.hasNext;
        _page++;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('history'))),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _items.length + 1,
          itemBuilder: (_, i) {
            if (i < _items.length) return HistoryTile(entry: _items[i]);
            if (_error != null) {
              return ErrorRetry(error: _error!, onRetry: _load);
            }
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: Text('No transactions yet')),
              );
            }
            return const SizedBox(height: 24);
          },
        ),
      ),
    );
  }
}
