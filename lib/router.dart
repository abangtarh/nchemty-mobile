import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pin_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/kyc/kyc_screen.dart';
import 'features/loans/products_screen.dart';
import 'features/momo/momo_screens.dart';
import 'features/qr/qr_screens.dart';
import 'features/transfer/transfer_screen.dart';

/// Every route outside /auth requires an unlocked session; the redirect
/// sends the member to the right auth screen whenever the state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<AuthStatus>(ref.read(authProvider).status);
  ref.listen(authProvider, (_, next) => refresh.value = next.status);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authProvider).status;
      final loc = state.matchedLocation;
      final target = switch (status) {
        AuthStatus.starting => '/splash',
        AuthStatus.loggedOut => '/auth/login',
        AuthStatus.needsPin => '/auth/create-pin',
        AuthStatus.locked => '/auth/unlock',
        AuthStatus.authenticated => null,
      };
      if (target != null) return loc == target ? null : target;
      // Authenticated: leave auth screens for home.
      if (loc.startsWith('/auth') || loc == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/create-pin', builder: (_, __) => const CreatePinScreen()),
      GoRoute(path: '/auth/unlock', builder: (_, __) => const UnlockScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/history/:type',
        builder: (_, s) => HistoryScreen(accountType: s.pathParameters['type']!),
      ),
      GoRoute(
        path: '/transfer',
        builder: (_, s) => TransferScreen(args: s.extra as TransferArgs?),
      ),
      GoRoute(path: '/momo/topup', builder: (_, __) => const TopupScreen()),
      GoRoute(path: '/momo/cashout', builder: (_, __) => const CashoutScreen()),
      GoRoute(path: '/products', builder: (_, __) => const ProductsScreen()),
      GoRoute(path: '/kyc', builder: (_, __) => const KycScreen()),
      GoRoute(path: '/qr/scan', builder: (_, __) => const ScanToPayScreen()),
      GoRoute(path: '/qr/receive', builder: (_, __) => const ReceiveQrScreen()),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF0F4C3A),
        body: Center(
          child: Text('Nchemty',
              style: TextStyle(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
        ),
      );
}
