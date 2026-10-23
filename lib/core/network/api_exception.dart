import 'package:dio/dio.dart';

/// One error type for the UI, whichever backend failed.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Cyclos error `code` (e.g. `login`, `confirmation`, `insufficientBalance`)
  /// or the middleware's `error` field.
  final String? code;

  bool get isUnauthorized => statusCode == 401;
  bool get isWrongConfirmation =>
      code == 'confirmation' || code == 'invalidConfirmation';

  factory ApiException.fromDio(DioException e) {
    final res = e.response;
    if (res == null) {
      return ApiException(
        e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout
            ? 'The connection is slow. Please try again.'
            : 'No connection. Check your data or Wi-Fi.',
      );
    }
    final data = res.data;
    String? code;
    String? message;
    if (data is Map) {
      code = (data['code'] ?? data['error'])?.toString();
      message = (data['message'] ?? data['errorMessage'])?.toString();
      // Cyclos validation errors: {"code":"validation","generalErrors":[...]}
      final general = data['generalErrors'];
      if (message == null && general is List && general.isNotEmpty) {
        message = general.first.toString();
      }
      final props = data['propertyErrors'];
      if (message == null && props is Map && props.isNotEmpty) {
        final first = props.values.first;
        message = first is List && first.isNotEmpty ? first.first.toString() : null;
      }
    }
    return ApiException(
      message ?? _defaultMessage(res.statusCode),
      statusCode: res.statusCode,
      code: code,
    );
  }

  static String _defaultMessage(int? status) => switch (status) {
        401 => 'Your session has ended. Please sign in again.',
        403 => 'You are not allowed to do this.',
        404 => 'Not found.',
        422 => 'Please check the details and try again.',
        _ => 'Something went wrong. Please try again.',
      };

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
