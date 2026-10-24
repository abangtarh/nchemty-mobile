import 'dart:convert';

import 'package:dio/dio.dart';

/// One error type for the UI, whichever backend failed.
///
/// Cyclos 4.16 error bodies (see the instance's openapi.json):
///  * 401 UnauthorizedError  {code: login|loggedOut|invalidChannelUsage|...}
///  * 403 ForbiddenError     {code: invalidPassword|permissionDenied|...}
///  * 404 NotFoundError      {entityType, key}
///  * 422 InputError         {code: validation, generalErrors, propertyErrors}
///  * 422 PaymentError       {kind: payment, code: insufficientBalance|...}
///  * 500 Error              {kind, exceptionType, exceptionMessage}
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code, this.details});

  final String message;
  final int? statusCode;

  /// Cyclos error `code` (e.g. `invalidPassword`, `insufficientBalance`).
  final String? code;

  /// Technical details for support: method, path, status and raw body.
  final String? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isWrongConfirmation =>
      code == 'invalidPassword' ||
      code == 'otpInvalidated' ||
      code == 'invalidDeviceConfirmation';
  bool get isNotFound => statusCode == 404;

  factory ApiException.fromDio(DioException e) {
    final req = e.requestOptions;
    final res = e.response;
    if (res == null) {
      return ApiException(
        e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout
            ? 'The connection is slow. Please try again.'
            : 'No connection. Check your data or Wi-Fi.',
        details: '${req.method} ${req.path}\n${e.type}: ${e.message}',
      );
    }
    final data = res.data;
    String? code;
    String? message;
    if (data is Map) {
      code = (data['code'] ?? data['error'])?.toString();
      message = (data['message'] ?? data['errorMessage'])?.toString();
      final general = data['generalErrors'];
      if (message == null && general is List && general.isNotEmpty) {
        message = general.join('\n');
      }
      final props = data['propertyErrors'];
      if (message == null && props is Map && props.isNotEmpty) {
        message = props.entries
            .map((p) => p.value is List ? (p.value as List).join(', ') : '${p.value}')
            .join('\n');
      }
      if (message == null && data['kind'] == 'payment') {
        message = _paymentMessage(code, data);
      }
      if (message == null && data['entityType'] != null) {
        message = 'Not found: ${data['entityType']}';
      }
      message ??= _codeMessage(code);
      message ??= data['exceptionMessage']?.toString();
    }
    String body;
    try {
      body = data is String ? data : const JsonEncoder.withIndent(' ').convert(data);
    } catch (_) {
      body = '$data';
    }
    return ApiException(
      message ?? _defaultMessage(res.statusCode),
      statusCode: res.statusCode,
      code: code,
      details: '${req.method} ${req.path}\nHTTP ${res.statusCode}\n$body',
    );
  }

  static String? _paymentMessage(String? code, Map data) => switch (code) {
        'insufficientBalance' => 'Not enough balance for this payment and its fees.',
        'dailyAmountExceeded' ||
        'weeklyAmountExceeded' ||
        'monthlyAmountExceeded' ||
        'yearlyAmountExceeded' ||
        'paymentAmountExceeded' =>
          'This is above your payment limit${data['maxAmount'] != null ? ' (max ${data['maxAmount']})' : ''}.',
        'dailyPaymentsExceeded' ||
        'weeklyPaymentsExceeded' ||
        'monthlyPaymentsExceeded' =>
          'You have reached the number of payments allowed for now.',
        'destinationUpperLimitReached' => 'The receiver\'s account cannot take this amount.',
        'timeBetweenPaymentsNotMet' => 'Please wait a moment before paying again.',
        _ => null,
      };

  static String? _codeMessage(String? code) => switch (code) {
        'invalidPassword' => 'Wrong PIN or password.',
        'otpInvalidated' => 'That code has expired. Request a new one.',
        'temporarilyBlocked' => 'Too many wrong attempts. Try again later.',
        'indefinitelyBlocked' => 'Your access is blocked. Please contact Nchemty.',
        'permissionDenied' => 'Your account is not allowed to do this.',
        'inaccessibleChannel' => 'Mobile access is not enabled for your account.',
        'invalidChannelUsage' => 'Mobile access is not enabled for your account.',
        'login' => 'Wrong username or password.',
        'loggedOut' => 'Your session has ended. Please sign in again.',
        'expiredPassword' => 'Your password has expired. Change it on the web, then sign in.',
        _ => null,
      };

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
