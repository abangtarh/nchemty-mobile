import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/l10n/strings.dart';
import 'core/push/push_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'data/cyclos/cyclos_inbox_api.dart';
import 'router.dart';

class NchemtyApp extends ConsumerStatefulWidget {
  const NchemtyApp({super.key});

  @override
  ConsumerState<NchemtyApp> createState() => _NchemtyAppState();
}

/// Locks the app after 5 min idle in the foreground or 60 s in the background.
class _NchemtyAppState extends ConsumerState<NchemtyApp>
    with WidgetsBindingObserver {
  Timer? _idle;
  DateTime? _backgroundedAt;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _subs = <StreamSubscription<Object?>>[];
  bool _openInbox = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetIdle();
    final push = ref.read(pushServiceProvider);
    // A push arrived while the app is open: refresh the bell, show a line.
    _subs.add(push.onForeground.listen((m) {
      ref.invalidate(inboxBadgeProvider);
      final n = m.notification;
      if (n == null) return;
      _messenger.currentState?.showSnackBar(SnackBar(
        content: Text([n.title, n.body].whereType<String>().join('\n')),
        action: SnackBarAction(label: 'Open', onPressed: _goInbox),
      ));
    }));
    // The member tapped a notification: open the inbox (after unlocking).
    _subs.add(push.onOpened.listen((_) => _goInbox()));
    push.initialMessage().then((m) {
      if (m != null) _goInbox();
    });
  }

  void _goInbox() {
    if (ref.read(authProvider).status == AuthStatus.authenticated) {
      ref.read(routerProvider).push('/inbox');
    } else {
      _openInbox = true; // after PIN / sign-in
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(Env.idleLockAfter, () => ref.read(authProvider.notifier).lock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null &&
          DateTime.now().difference(since) > Env.backgroundLockAfter) {
        ref.read(authProvider.notifier).lock();
      }
      _resetIdle();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Each time the member gets in (password, PIN or fingerprint): register
    // this phone for push, and open the inbox if a notification was tapped.
    ref.listen(authProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        ref.read(pushServiceProvider).registerForMember();
        if (_openInbox) {
          _openInbox = false;
          Future.microtask(() => ref.read(routerProvider).push('/inbox'));
        }
      }
    });
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdle(),
      child: MaterialApp.router(
        title: 'Nchemty',
        scaffoldMessengerKey: _messenger,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: router,
        locale: locale,
        supportedLocales: S.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
