import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../../core/storage/secure_store.dart';
import '../../data/cyclos/cyclos_api.dart';
import '../../data/models/models.dart';

enum AuthStatus {
  /// Reading storage at startup.
  starting,

  /// No stored session: show username/password.
  loggedOut,

  /// Signed in but no local PIN yet: ask the member to create one.
  needsPin,

  /// Stored session, app locked: PIN or biometrics to continue.
  locked,

  /// Unlocked and session valid.
  authenticated,
}

class AuthState {
  const AuthState(this.status, {this.user, this.error});
  final AuthStatus status;
  final CyclosUser? user;
  final String? error;

  AuthState copyWith({AuthStatus? status, CyclosUser? user, String? error}) =>
      AuthState(status ?? this.status, user: user ?? this.user, error: error);
}

/// Flow:
///  1. Password login -> Cyclos session token (kept in secure storage).
///  2. Member creates a local PIN; biometrics optional.
///  3. Later launches: PIN/biometrics unlock the stored token, then
///     GET /auth confirms Cyclos still accepts it. Expired -> password again.
///
/// TODO(cyclos): replace the local PIN with Cyclos device PINs once the
/// feature is confirmed on the instance, so Cyclos also verifies the PIN.
class AuthController extends Notifier<AuthState> {
  late final SecureStore _store = ref.read(secureStoreProvider);
  late final SessionHolder _session = ref.read(sessionHolderProvider);
  late final CyclosApi _api = ref.read(cyclosApiProvider);
  final _localAuth = LocalAuthentication();
  int _failedPins = 0;

  @override
  AuthState build() {
    _session.onUnauthorized = _onUnauthorized;
    Future.microtask(_restore);
    return const AuthState(AuthStatus.starting);
  }

  Future<void> _restore() async {
    final token = await _store.readSession();
    if (token == null) {
      state = const AuthState(AuthStatus.loggedOut);
    } else if (!await _store.hasPin()) {
      // Session saved but PIN never set: start clean.
      await _store.clearSession();
      state = const AuthState(AuthStatus.loggedOut);
    } else {
      state = const AuthState(AuthStatus.locked);
    }
  }

  Future<void> loginWithPassword(String username, String password) async {
    state = state.copyWith(error: null);
    try {
      final result = await _api.login(username.trim(), password);
      _session.token = result.token;
      await _store.writeSession(result.token);
      _failedPins = 0;
      state = AuthState(
        await _store.hasPin() ? AuthStatus.authenticated : AuthStatus.needsPin,
        user: result.user,
      );
    } on ApiException catch (e) {
      state = AuthState(AuthStatus.loggedOut,
          error: e.statusCode == 401
              ? 'Wrong username or password.'
              : e.message);
    }
  }

  Future<void> createPin(String pin) async {
    await _store.setPin(pin);
    state = state.copyWith(status: AuthStatus.authenticated);
  }

  Future<bool> unlockWithPin(String pin) async {
    if (!await _store.verifyPin(pin)) {
      _failedPins++;
      if (_failedPins >= 5) {
        await logout();
        state = const AuthState(AuthStatus.loggedOut,
            error: 'Too many wrong PINs. Sign in with your password.');
      } else {
        state = state.copyWith(error: 'Wrong PIN (${5 - _failedPins} left)');
      }
      return false;
    }
    return _resumeSession();
  }

  Future<bool> canUseBiometrics() async {
    if (!await _store.biometricsEnabled()) return false;
    try {
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock Nchemty',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      return ok ? _resumeSession() : false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometrics(bool on) => _store.setBiometrics(on);

  Future<bool> _resumeSession() async {
    final token = await _store.readSession();
    if (token == null) {
      state = const AuthState(AuthStatus.loggedOut);
      return false;
    }
    _session.token = token;
    try {
      final user = await _api.currentUser();
      _failedPins = 0;
      state = AuthState(AuthStatus.authenticated, user: user);
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _store.clearSession();
        _session.token = null;
        state = const AuthState(AuthStatus.loggedOut,
            error: 'Your session has ended. Please sign in again.');
      } else {
        state = state.copyWith(error: e.message);
      }
      return false;
    }
  }

  /// Called by the lifecycle observer after idle/background timeouts.
  void lock() {
    if (state.status != AuthStatus.authenticated) return;
    _session.token = null;
    state = AuthState(AuthStatus.locked, user: state.user);
  }

  Future<void> logout() async {
    try {
      if (_session.token != null) await _api.logout();
    } catch (_) {
      // Logging out locally matters more than the server call.
    }
    _session.token = null;
    await _store.clearSession();
    state = const AuthState(AuthStatus.loggedOut);
  }

  /// "Forget this device": also removes the PIN and settings.
  Future<void> forgetDevice() async {
    await logout();
    await _store.wipe();
  }

  void _onUnauthorized() {
    if (state.status == AuthStatus.authenticated) {
      _session.token = null;
      _store.clearSession();
      state = const AuthState(AuthStatus.loggedOut,
          error: 'Your session has ended. Please sign in again.');
    }
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
