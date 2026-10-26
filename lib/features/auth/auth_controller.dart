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

/// Flow ("remember me"):
///  1. Password login -> Cyclos session token. The username is remembered.
///  2. Member creates a PIN. It is registered with Cyclos as a device PIN
///     (POST /device-pins), so Cyclos itself checks it, and kept as a local
///     hash for a quick offline check.
///  3. Later launches: PIN (or biometrics) -> reuse the stored session if
///     Cyclos still accepts it, otherwise open a NEW session with the device
///     PIN. The password is only needed again if Cyclos removes the PIN
///     (too many wrong tries) or the member signs out.
///  If device PINs are off for the channel, step 3 falls back to the stored
///  session only, which ends with Cyclos's session timeout.
class AuthController extends Notifier<AuthState> {
  late final SecureStore _store = ref.read(secureStoreProvider);
  late final SessionHolder _session = ref.read(sessionHolderProvider);
  late final CyclosApi _api = ref.read(cyclosApiProvider);
  final _localAuth = LocalAuthentication();
  int _failedPins = 0;

  /// From the password login, to register the device PIN (6-minute token;
  /// the password is the fallback). Memory only, cleared after use.
  String? _pinCreationToken;
  String? _password;

  @override
  AuthState build() {
    _session.onUnauthorized = _onUnauthorized;
    Future.microtask(_restore);
    return const AuthState(AuthStatus.starting);
  }

  Future<void> _restore() async {
    final hasPin = await _store.hasPin();
    final devicePin = await _store.readDevicePin();
    final token = await _store.readSession();
    final name = await _store.readUserName();
    final user = name == null ? null : CyclosUser(id: '', display: name);
    if (hasPin && (devicePin != null || token != null)) {
      state = AuthState(AuthStatus.locked, user: user);
    } else {
      await _store.clearSession();
      state = const AuthState(AuthStatus.loggedOut);
    }
  }

  Future<void> loginWithPassword(String username, String password) async {
    state = state.copyWith(error: null);
    try {
      final result = await _api.login(username.trim(), password);
      _session.token = result.token;
      await _store.writeSession(result.token);
      await _store.writeLastUsername(username.trim());
      await _store.writeUserName(result.user.display);
      _failedPins = 0;
      final hasPin = await _store.hasPin();
      if (hasPin && await _store.readDevicePin() == null) {
        // Older install (local PIN only): ask for a PIN again so it can be
        // registered with Cyclos.
        await _store.clearPin();
      }
      _pinCreationToken = result.pinCreationToken;
      _password = password;
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

  /// Registers the PIN with Cyclos and locally. Returns an error message
  /// when Cyclos rejects the PIN (too simple, wrong length) so the member
  /// can choose another; null on success.
  Future<String?> createPin(String pin, {required bool biometrics}) async {
    Future<({String principal, String salt})> register({required bool withToken}) =>
        _api.createDevicePin(
          name: 'Nchemty app',
          pin: pin,
          pinCreationToken: withToken ? _pinCreationToken : null,
          currentPassword: withToken ? null : _password,
        );
    try {
      late ({String principal, String salt}) created;
      try {
        created = await register(withToken: _pinCreationToken != null);
      } on ApiException catch (e) {
        // The 6-minute token expired: confirm with the password instead.
        if (_pinCreationToken == null || _password == null || e.statusCode == 422) rethrow;
        created = await register(withToken: false);
      }
      await _store.writeDevicePin(created.principal, created.salt);
    } on ApiException catch (e) {
      // PIN rules (too simple, wrong length): keep the token and password
      // in memory so the member's next choice can still be registered.
      if (e.statusCode == 422) return e.message;
      // Device PINs not enabled for this channel (or offline): keep a
      // local PIN; unlocking then works while the session lasts.
      await _store.clearDevicePin();
    }
    _pinCreationToken = null;
    _password = null;
    await _store.setPin(pin);
    await _store.setBiometrics(biometrics);
    await _store.writeBioPin(biometrics ? pin : null);
    state = state.copyWith(status: AuthStatus.authenticated);
    return null;
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
    return _resumeSession(pin);
  }

  /// Whether this phone has fingerprint / Face ID set up.
  Future<bool> biometricsAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
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
      return ok ? await _resumeSession(await _store.readBioPin()) : false;
    } catch (_) {
      return false;
    }
  }

  /// 1. Reuse the stored session while Cyclos accepts it.
  /// 2. Otherwise open a new session with the Cyclos device PIN.
  /// 3. Only if that is impossible, ask for the password.
  Future<bool> _resumeSession(String? pin) async {
    final token = await _store.readSession();
    if (token != null) {
      _session.token = token;
      try {
        final user = await _api.currentUser();
        _failedPins = 0;
        state = AuthState(AuthStatus.authenticated, user: user);
        return true;
      } on ApiException catch (e) {
        if (!e.isUnauthorized) {
          state = state.copyWith(error: e.message);
          return false;
        }
        await _store.clearSession();
        _session.token = null;
      }
    }

    final devicePin = await _store.readDevicePin();
    if (devicePin == null) {
      state = const AuthState(AuthStatus.loggedOut,
          error: 'Your session has ended. Please sign in again.');
      return false;
    }
    if (pin == null) {
      // Biometrics without a stored PIN: type the PIN once.
      state = AuthState(AuthStatus.locked,
          user: state.user, error: 'Enter your PIN to continue.');
      return false;
    }
    try {
      final r = await _api.loginWithDevicePin(devicePin.principal, devicePin.salt, pin);
      _session.token = r.token;
      await _store.writeSession(r.token);
      await _store.writeUserName(r.user.display);
      _failedPins = 0;
      state = AuthState(AuthStatus.authenticated, user: r.user);
      return true;
    } on ApiException catch (e) {
      if (e.code == 'devicePinRemoved' || e.statusCode == 401 || e.statusCode == 403) {
        // Cyclos no longer accepts this PIN (removed, blocked or reset).
        await _store.clearSession();
        await _store.clearPin();
        state = AuthState(AuthStatus.loggedOut,
            error: e.code == 'devicePinRemoved'
                ? 'Your PIN was removed after too many attempts. Sign in with your password.'
                : 'Please sign in with your password to set up your PIN again.');
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

  /// Sign out: ends the session and forgets the PIN on this phone, so the
  /// next start asks for the password (the username stays filled in).
  Future<void> logout() async {
    try {
      if (_session.token != null) await _api.logout();
    } catch (_) {
      // Logging out locally matters more than the server call.
    }
    _session.token = null;
    await _store.clearSession();
    await _store.clearPin();
    state = const AuthState(AuthStatus.loggedOut);
  }

  /// "Forget this device": also removes the PIN and settings.
  Future<void> forgetDevice() async {
    await logout();
    await _store.wipe();
  }

  /// The session expired while the app was open: with a device PIN the
  /// member just re-enters the PIN; without one, the password.
  Future<void> _onUnauthorized() async {
    if (state.status != AuthStatus.authenticated) return;
    _session.token = null;
    await _store.clearSession();
    if (await _store.readDevicePin() != null && await _store.hasPin()) {
      state = AuthState(AuthStatus.locked,
          user: state.user, error: 'Your session timed out. Enter your PIN.');
    } else {
      state = const AuthState(AuthStatus.loggedOut,
          error: 'Your session has ended. Please sign in again.');
    }
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
