import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/dio_factory.dart';
import 'firebase_options.dart';

/// Push notifications through Firebase Cloud Messaging.
///
/// Cyclos sends the push itself (its Firebase settings must point at project
/// nchemty-d07fd). The app only registers this phone's FCM token with the
/// signed-in member (POST /firebase/fcm-tokens), refreshes it when Firebase
/// rotates it (PUT), and removes it on sign-out (DELETE).
class PushService {
  PushService(this._dio);
  final Dio _dio;

  static bool _ready = false;
  String? _token;
  StreamSubscription<String>? _refresh;

  /// Call once from main(); never throws (push is optional).
  static Future<void> init() async {
    final options = NchemtyFirebaseOptions.currentPlatform;
    if (options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      _ready = true;
    } catch (e) {
      debugPrint('Push: Firebase init failed: $e');
    }
  }

  /// After sign-in / unlock: ask permission (Android 13+, iOS) and register.
  Future<void> registerForMember() async {
    if (!_ready) return;
    try {
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      await fm.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);
      final token = await fm.getToken();
      if (token == null) return;
      _token = token;
      await _dio.post<void>('/firebase/fcm-tokens',
          data: token, options: Options(contentType: 'text/plain'));
      _refresh ??= fm.onTokenRefresh.listen((newToken) async {
        final old = _token;
        _token = newToken;
        try {
          if (old == null) {
            await _dio.post<void>('/firebase/fcm-tokens',
                data: newToken, options: Options(contentType: 'text/plain'));
          } else {
            await _dio.put<void>('/firebase/fcm-tokens',
                data: {'oldToken': old, 'newToken': newToken});
          }
        } catch (_) {}
      });
    } catch (e) {
      // No Google Play services (e.g. Huawei), permission refused, offline:
      // the in-app inbox still works.
      debugPrint('Push: registration skipped: $e');
    }
  }

  /// Before sign-out (while the session is still valid).
  Future<void> unregister() async {
    if (!_ready) return;
    final token = _token ?? await FirebaseMessaging.instance.getToken().catchError((_) => null);
    if (token == null) return;
    try {
      await _dio.delete<void>('/firebase/fcm-tokens', data: {'token': token});
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }

  /// Notifications that arrive while the app is open.
  Stream<RemoteMessage> get onForeground =>
      _ready ? FirebaseMessaging.onMessage : const Stream.empty();

  /// The member tapped a notification (app in background).
  Stream<RemoteMessage> get onOpened =>
      _ready ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();

  /// The app was started by tapping a notification.
  Future<RemoteMessage?> initialMessage() async =>
      _ready ? FirebaseMessaging.instance.getInitialMessage() : null;
}

final pushServiceProvider =
    Provider<PushService>((ref) => PushService(ref.watch(cyclosDioProvider)));
