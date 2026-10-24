import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../models/models.dart';

/// Direct calls to the Cyclos 4.16.17 REST API (`/api`).
/// Paths follow the Cyclos OpenAPI descriptor; confirm them against your
/// instance's /api/openapi.yaml before release.
class CyclosApi {
  CyclosApi(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /auth/session with Basic auth. Returns the session token + user.
  Future<({String token, CyclosUser user})> login(
      String username, String password) {
    return _guard(() async {
      final basic = base64Encode(utf8.encode('$username:$password'));
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/session',
        options: Options(headers: {'Authorization': 'Basic $basic'}),
      );
      final data = res.data!;
      return (
        token: data['sessionToken'].toString(),
        user: CyclosUser.fromJson(
            (data['user'] as Map).cast<String, dynamic>()),
      );
    });
  }

  /// GET /auth — validates the current token and returns the logged user.
  Future<CyclosUser> currentUser() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/auth');
        return CyclosUser.fromJson(
            (res.data!['user'] as Map).cast<String, dynamic>());
      });

  Future<void> logout() => _guard(() => _dio.delete<void>('/auth/session'));

  Future<List<Account>> accounts() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/self/accounts');
        return res.data!
            .map((e) => Account.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<HistoryPage> history(
    String accountType, {
    int page = 0,
    int pageSize = 20,
    DateTime? from,
    DateTime? to,
  }) =>
      _guard(() async {
        final res = await _dio.get<List<dynamic>>(
          '/self/accounts/$accountType/history',
          queryParameters: {
            'page': page,
            'pageSize': pageSize,
            if (from != null || to != null)
              'datePeriod': [
                from?.toUtc().toIso8601String() ?? '',
                to?.toUtc().toIso8601String() ?? '',
              ].join(','),
          },
        );
        final hasNext = res.headers.value('X-Has-Next-Page') == 'true';
        return HistoryPage(
          res.data!
              .map((e) =>
                  HistoryEntry.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
          hasNext: hasNext,
        );
      });

  /// Find a payee by phone, account number or username (as Cyclos
  /// keyword-search is configured for the member product).
  Future<List<CyclosUser>> searchUsers(String keywords) => _guard(() async {
        final res = await _dio.get<List<dynamic>>(
          '/users',
          queryParameters: {'keywords': keywords, 'pageSize': 10},
        );
        return res.data!
            .map((e) => CyclosUser.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// GET /self/payments/data-for-perform?to=… — who the payee really is and
  /// which payment types this member may use towards them.
  Future<PaymentData> paymentData(String to) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/self/payments/data-for-perform',
          queryParameters: {'to': to},
        );
        return PaymentData.fromJson(res.data!);
      });

  Map<String, dynamic> _paymentBody(String subject, num amount, String? type,
          String? description) =>
      {
        'subject': subject,
        'amount': amount.toString(),
        if (type != null) 'type': type,
        if (description != null && description.isNotEmpty)
          'description': description,
      };

  /// POST /self/payments/preview — fees, total and how to confirm.
  Future<PaymentPreview> previewPayment({
    required String subject,
    required num amount,
    String? paymentType,
    String? description,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/self/payments/preview',
          data: _paymentBody(subject, amount, paymentType, description),
        );
        return PaymentPreview.fromJson(res.data!);
      });

  /// POST /self/payments. Cyclos reads the credential from the
  /// `confirmationPassword` header (see the instance's openapi.json).
  Future<String> performPayment({
    required String subject,
    required num amount,
    String? confirmationPassword,
    String? paymentType,
    String? description,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/self/payments',
          data: _paymentBody(subject, amount, paymentType, description),
          options: Options(headers: {
            if (confirmationPassword != null)
              'confirmationPassword': confirmationPassword,
          }),
        );
        return (res.data?['transactionNumber'] ?? res.data?['id']).toString();
      });

  /// POST /auth/otp?medium=sms — sends a one-time code when the
  /// confirmation password type is an OTP.
  Future<void> sendOtp({String medium = 'sms'}) => _guard(
      () => _dio.post<void>('/auth/otp', queryParameters: {'medium': medium}));
}

final cyclosApiProvider =
    Provider<CyclosApi>((ref) => CyclosApi(ref.watch(cyclosDioProvider)));
