import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain (iOS) / Keystore-backed storage (Android). Nothing sensitive
/// is ever written to shared preferences or plain files.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _s;

  static const _kSession = 'cyclos_session_token';
  static const _kPinHash = 'local_pin_hash';
  static const _kPinSalt = 'local_pin_salt';
  static const _kBiometrics = 'biometrics_enabled';
  static const _kLocale = 'locale';

  Future<String?> readSession() => _s.read(key: _kSession);
  Future<void> writeSession(String token) =>
      _s.write(key: _kSession, value: token);
  Future<void> clearSession() => _s.delete(key: _kSession);

  Future<bool> hasPin() async => (await _s.read(key: _kPinHash)) != null;

  Future<void> setPin(String pin) async {
    final salt = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    await _s.write(key: _kPinSalt, value: salt);
    await _s.write(key: _kPinHash, value: _hash(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _s.read(key: _kPinSalt);
    final hash = await _s.read(key: _kPinHash);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  Future<bool> biometricsEnabled() async =>
      (await _s.read(key: _kBiometrics)) == 'true';
  Future<void> setBiometrics(bool on) =>
      _s.write(key: _kBiometrics, value: on.toString());

  Future<String?> readLocale() => _s.read(key: _kLocale);
  Future<void> writeLocale(String code) => _s.write(key: _kLocale, value: code);

  /// Full wipe on logout or "forget this device".
  Future<void> wipe() => _s.deleteAll();

  static String _hash(String pin, String salt) {
    // utf8.encode returns Uint8List; type as List<int> so `.bytes` can be
    // reassigned below.
    List<int> digest = utf8.encode('$salt:$pin');
    // Cheap stretching; the real guard is Cyclos rejecting a stale session.
    for (var i = 0; i < 10000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }
}

final secureStoreProvider = Provider<SecureStore>((_) => SecureStore());
