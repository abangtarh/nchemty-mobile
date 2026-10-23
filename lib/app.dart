import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/l10n/strings.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetIdle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
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
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdle(),
      child: MaterialApp.router(
        title: 'Nchemty',
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
