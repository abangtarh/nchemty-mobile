import 'dart:convert';
import 'dart:typed_data';

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

  /// Same as the official frontend's ApiHelper.escapeNumeric: a purely
  /// numeric value is prefixed with `'` so Cyclos reads it as a phone or
  /// account number instead of an internal id.
  static String escapeNumeric(String value) {
    final v = value.trim();
    return RegExp(r'^[-+]?\d+$').hasMatch(v) ? "'$v" : v;
  }

  /// Quick search for the payee field (GET /users?keywords=…), excluding
  /// the member themself — as the official user field does.
  Future<List<CyclosUser>> searchUsers(String keywords) => _guard(() async {
        final res = await _dio.get<List<dynamic>>(
          '/users',
          queryParameters: {
            'keywords': keywords,
            'pageSize': 10,
            'usersToExclude': 'self',
          },
        );
        return res.data!
            .map((e) => CyclosUser.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// GET /users/{locator}/locate — finds a member by any identifier.
  /// Use `*:<value>` to try every principal type (QR tokens included).
  Future<CyclosUser> locateUser(String locator) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
            '/users/${Uri.encodeComponent(locator)}/locate');
        return CyclosUser.fromJson(res.data!);
      });

  /// GET /self/payments/data-for-perform.
  ///  * no args: the accounts the member can pay from;
  ///  * [to]: the payee and the payment types towards them;
  ///  * [to] + [type]: the rules of that payment type.
  Future<PaymentData> paymentData({String? to, String? type}) =>
      _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/self/payments/data-for-perform',
          queryParameters: {
            if (to != null) 'to': to,
            if (type != null) 'type': type,
          },
        );
        return PaymentData.fromJson(res.data!);
      });

  /// POST /self/payments/preview. [body] is a Cyclos PerformPayment:
  /// subject, type, amount, description, scheduling fields.
  Future<PaymentPreview> previewPayment(Map<String, dynamic> body) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            '/self/payments/preview',
            data: body);
        return PaymentPreview.fromJson(res.data!);
      });

  /// POST /self/payments with the preview's normalised payment. Cyclos reads
  /// the credential from the `confirmationPassword` header.
  Future<String> performPayment(Map<String, dynamic> payment,
          {String? confirmationPassword}) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/self/payments',
          data: payment,
          options: Options(headers: {
            if (confirmationPassword != null)
              'confirmationPassword': confirmationPassword,
          }),
        );
        return (res.data?['transactionNumber'] ?? res.data?['id']).toString();
      });

  /// GET /transfers/{key} — details of one history entry.
  /// If [key] is a payment's transaction number rather than a transfer's,
  /// falls back to GET /transactions/{key} and opens its generated transfer.
  Future<TransferDetails> transfer(String key) => _guard(() async {
        try {
          final res = await _dio.get<Map<String, dynamic>>(
              '/transfers/${Uri.encodeComponent(key)}');
          return TransferDetails.fromJson(res.data!);
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
          final tx = await _dio.get<Map<String, dynamic>>(
              '/transactions/${Uri.encodeComponent(key)}');
          final transferId = (tx.data?['transfer'] as Map?)?['id'];
          if (transferId == null) rethrow;
          final res = await _dio.get<Map<String, dynamic>>('/transfers/$transferId');
          return TransferDetails.fromJson(res.data!);
        }
      });

  /// GET /transfers/{key}/export/{format} — the official Cyclos file
  /// (e.g. PDF receipt) for one transfer.
  Future<Uint8List> exportTransfer(String key, String format) => _guard(() async {
        final res = await _dio.get<List<int>>(
          '/transfers/${Uri.encodeComponent(key)}/export/${Uri.encodeComponent(format)}',
          options: Options(responseType: ResponseType.bytes, headers: {'Accept': '*/*'}),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  /// POST /auth/otp?medium=sms — sends a one-time code when the
  /// confirmation password type is an OTP.
  Future<void> sendOtp({String medium = 'sms'}) => _guard(
      () => _dio.post<void>('/auth/otp', queryParameters: {'medium': medium}));
}

final cyclosApiProvider =
    Provider<CyclosApi>((ref) => CyclosApi(ref.watch(cyclosDioProvider)));
