import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

/// Called when any backend answers 401, so the app can lock or log out.
typedef UnauthorizedHandler = void Function();

/// Shared session-token holder. The token lives in memory while the app is
/// unlocked and in secure storage between launches.
class SessionHolder {
  String? token;
  UnauthorizedHandler? onUnauthorized;
}

final sessionHolderProvider = Provider<SessionHolder>((_) => SessionHolder());

Dio _baseDio(String baseUrl) => Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: {'Accept': 'application/json'},
      ),
    );

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this.session, {required this.forCyclos});

  final SessionHolder session;
  final bool forCyclos;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = session.token;
    if (token != null && !options.headers.containsKey('Authorization')) {
      // Cyclos reads `Session-Token`; the middleware receives the same token
      // and resolves the member by calling Cyclos GET /auth with it.
      options.headers[forCyclos ? 'Session-Token' : 'X-Cyclos-Session'] = token;
    }
    if (forCyclos) options.headers['Channel'] = Env.cyclosChannel;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final isLoginCall = err.requestOptions.path.startsWith('/auth/session') &&
        err.requestOptions.method == 'POST';
    if (err.response?.statusCode == 401 && !isLoginCall) {
      session.onUnauthorized?.call();
    }
    handler.next(err);
  }
}

class _RetryOnNetworkError extends Interceptor {
  _RetryOnNetworkError(this.dio);
  final Dio dio;

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final attempt = (opts.extra['attempt'] as int?) ?? 0;
    // Only retry safe reads; never replay a payment.
    final retryable = opts.method == 'GET' &&
        attempt < 2 &&
        (err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.connectionTimeout);
    if (!retryable) return handler.next(err);
    await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    opts.extra['attempt'] = attempt + 1;
    try {
      handler.resolve(await dio.fetch(opts));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

Dio _build(String baseUrl, SessionHolder session, {required bool forCyclos}) {
  final dio = _baseDio(baseUrl);
  dio.interceptors.add(_AuthInterceptor(session, forCyclos: forCyclos));
  dio.interceptors.add(_RetryOnNetworkError(dio));
  if (kDebugMode && !Env.isProd) {
    // Headers are not logged, so tokens and PINs never reach the console.
    dio.interceptors.add(LogInterceptor(
      requestHeader: false,
      responseHeader: false,
      requestBody: false,
      responseBody: false,
      logPrint: (o) => debugPrint(o.toString()),
    ));
  }
  // TODO(security): add certificate pinning for ebank/brg1 before release,
  // e.g. via IOHttpClientAdapter.validateCertificate with SHA-256 pins.
  return dio;
}

final cyclosDioProvider = Provider<Dio>((ref) =>
    _build(Env.cyclosBaseUrl, ref.watch(sessionHolderProvider), forCyclos: true));

final hubDioProvider = Provider<Dio>((ref) =>
    _build(Env.hubBaseUrl, ref.watch(sessionHolderProvider), forCyclos: false));
