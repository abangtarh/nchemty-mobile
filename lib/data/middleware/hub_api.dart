import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../models/models.dart';

/// Calls to the Node middleware / Payment Hub (`/v1`). The contract is in
/// docs/middleware-contract.md. The hub resolves the member from the
/// forwarded Cyclos session token; the app never sends a member id.
class HubApi {
  HubApi(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Idempotency key so a retried tap never moves money twice.
  static String newIdempotencyKey() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ---- Loans (wraps LoanCoreLib operations) ----

  Future<List<Loan>> loans() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/loans');
        return res.data!
            .map((e) => Loan.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<Map<String, dynamic>> applyForLoan({
    required String productCode,
    required int amount,
    required int termMonths,
    String? purpose,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/loans/apply', data: {
          'productCode': productCode,
          'amount': amount,
          'termMonths': termMonths,
          if (purpose != null) 'purpose': purpose,
        });
        return res.data!;
      });

  Future<void> repayLoan({
    required String loanId,
    required int amount,
    required String confirmationPassword,
    required String idempotencyKey,
  }) =>
      _guard(() => _dio.post<void>(
            '/loans/$loanId/repay',
            data: {'amount': amount},
            options: Options(headers: {
              'Confirmation-Password': confirmationPassword,
              'Idempotency-Key': idempotencyKey,
            }),
          ));

  // ---- ACAO DailySaver (wraps ACAOCoreLib) ----

  Future<List<SavingsProduct>> savingsProducts() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/savings/products');
        return res.data!
            .map((e) =>
                SavingsProduct.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<void> subscribeSavings({
    required String productCode,
    required int initialDeposit,
    required bool acceptTerms,
    required String confirmationPassword,
  }) =>
      _guard(() => _dio.post<void>(
            '/savings/subscribe',
            data: {
              'productCode': productCode,
              'initialDeposit': initialDeposit,
              'acceptTerms': acceptTerms,
            },
            options:
                Options(headers: {'Confirmation-Password': confirmationPassword}),
          ));
}

final hubApiProvider =
    Provider<HubApi>((ref) => HubApi(ref.watch(hubDioProvider)));
