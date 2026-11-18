import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';

num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
num? _nOrNull(Object? v) => v == null ? null : (v is num ? v : num.tryParse('$v'));
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

// ── Savings (ACAO DailySaver) ──────────────────────────────────────────────

class AcaoTerm {
  const AcaoTerm({required this.code, required this.days, this.ratePa});
  final String code;
  final int days;
  final num? ratePa;

  factory AcaoTerm.fromJson(Map<String, dynamic> j) => AcaoTerm(
        code: '${j['term_code']}',
        days: _n(j['days']).toInt(),
        ratePa: _nOrNull(j['interest_rate_pa']),
      );
}

class AcaoProduct {
  const AcaoProduct({
    required this.id,
    required this.name,
    required this.terms,
    required this.ratesPublished,
    this.rateYear,
    this.depositCeiling,
    this.applicationFee,
    this.setupFee,
    this.penaltyPct,
  });
  final String id;
  final String name;
  final List<AcaoTerm> terms;
  final bool ratesPublished;
  final int? rateYear;
  final num? depositCeiling;
  final num? applicationFee;
  final num? setupFee;
  final num? penaltyPct;

  factory AcaoProduct.fromJson(Map<String, dynamic> j) => AcaoProduct(
        id: '${j['id']}',
        name: '${j['name'] ?? j['id']}',
        terms: [
          for (final t in (j['terms'] as List?) ?? const [])
            AcaoTerm.fromJson((t as Map).cast<String, dynamic>()),
        ],
        ratesPublished: j['rates_published'] == true,
        rateYear: _nOrNull(j['rate_year'])?.toInt(),
        depositCeiling: _nOrNull(j['deposit_ceiling']),
        applicationFee: _nOrNull(j['application_fee']),
        setupFee: _nOrNull(j['setup_fee']),
        penaltyPct: _nOrNull(j['penalty_pct_of_interest']),
      );
}

class AcaoSavingsAccount {
  const AcaoSavingsAccount({
    required this.id,
    required this.productName,
    required this.termCode,
    required this.status,
    required this.principal,
    required this.accruedInterest,
    this.termStart,
    this.maturity,
    this.currentRatePa,
    this.accruedThrough,
    this.penaltyPct,
    this.payoutPrincipal,
    this.payoutInterest,
    this.penaltyForfeited,
  });
  final String id;
  final String productName;
  final String termCode;

  /// active / matured / closed
  final String status;
  final num principal;
  final num accruedInterest;
  final DateTime? termStart;
  final DateTime? maturity;
  final num? currentRatePa;
  final String? accruedThrough;
  final num? penaltyPct;
  final num? payoutPrincipal;
  final num? payoutInterest;
  final num? penaltyForfeited;

  bool get isActive => status == 'active';

  factory AcaoSavingsAccount.fromJson(Map<String, dynamic> j) => AcaoSavingsAccount(
        id: '${j['id']}',
        productName: '${j['product_name'] ?? 'Savings'}',
        termCode: '${j['term_code'] ?? ''}',
        status: '${j['status'] ?? ''}',
        principal: _n(j['principal']),
        accruedInterest: _n(j['accrued_interest']),
        termStart: _d(j['term_start_date']),
        maturity: _d(j['maturity_date']),
        currentRatePa: _nOrNull(j['current_rate_pa']),
        accruedThrough: j['accrued_through'] as String?,
        penaltyPct: _nOrNull(j['penalty_pct_of_interest']),
        payoutPrincipal: _nOrNull(j['payout_principal']),
        payoutInterest: _nOrNull(j['payout_interest']),
        penaltyForfeited: _nOrNull(j['penalty_forfeited']),
      );
}

class AcaoWithdrawalQuote {
  const AcaoWithdrawalQuote({
    required this.accountId,
    required this.principal,
    required this.accruedInterest,
    required this.penaltyPct,
    required this.penalty,
    required this.totalPayout,
  });
  final String accountId;
  final num principal;
  final num accruedInterest;
  final num penaltyPct;
  final num penalty;
  final num totalPayout;

  factory AcaoWithdrawalQuote.fromJson(Map<String, dynamic> j) => AcaoWithdrawalQuote(
        accountId: '${j['savingsAccountId']}',
        principal: _n(j['principal']),
        accruedInterest: _n(j['accruedInterest']),
        penaltyPct: _n(j['penaltyPct']),
        penalty: _n(j['penalty']),
        totalPayout: _n(j['totalPayout']),
      );
}

// ── Loans ─────────────────────────────────────────────────────────────────

class AcaoAuthorization {
  const AcaoAuthorization({required this.level, this.decision});
  final String level;

  /// approved / rejected / null (pending)
  final String? decision;

  String get levelLabel => switch (level) {
        'branch_manager' => 'Branch manager',
        'operations_manager' => 'Operations manager',
        'credit_committee' => 'Credit committee',
        _ => level.replaceAll('_', ' '),
      };
}

class AcaoLoanApplication {
  const AcaoLoanApplication({
    required this.id,
    required this.reference,
    required this.amount,
    required this.status,
    required this.authorizations,
    this.termMonths,
    this.purpose,
    this.createdAt,
  });
  final String id;
  final String reference;
  final num amount;
  final String status;
  final List<AcaoAuthorization> authorizations;
  final int? termMonths;
  final String? purpose;
  final DateTime? createdAt;

  factory AcaoLoanApplication.fromJson(Map<String, dynamic> j) => AcaoLoanApplication(
        id: '${j['id']}',
        reference: '${j['reference'] ?? ''}',
        amount: _n(j['requested_amount']),
        status: '${j['status'] ?? 'pending'}',
        termMonths: _nOrNull(j['term_months'])?.toInt(),
        purpose: j['purpose'] as String?,
        createdAt: _d(j['created_at']),
        authorizations: [
          for (final a in (j['authorizations'] as List?) ?? const [])
            AcaoAuthorization(
              level: '${(a as Map)['level']}',
              decision: a['decision'] as String?,
            ),
        ],
      );
}

class AcaoInstallment {
  const AcaoInstallment({
    required this.no,
    required this.principalDue,
    required this.interestDue,
    required this.status,
    this.dueDate,
  });
  final int no;
  final num principalDue;
  final num interestDue;
  final String status;
  final DateTime? dueDate;

  num get total => principalDue + interestDue;
}

class AcaoLoan {
  const AcaoLoan({
    required this.id,
    required this.reference,
    required this.principal,
    required this.status,
    this.ratePa,
    this.grantedAt,
    this.schedule = const [],
  });
  final String id;
  final String reference;
  final num principal;
  final String status;
  final num? ratePa;
  final DateTime? grantedAt;
  final List<AcaoInstallment> schedule;

  factory AcaoLoan.fromJson(Map<String, dynamic> j) => AcaoLoan(
        id: '${j['id']}',
        reference: '${j['reference'] ?? ''}',
        principal: _n(j['principal']),
        status: '${j['status'] ?? ''}',
        ratePa: _nOrNull(j['interest_rate_pa']),
        grantedAt: _d(j['granted_at']),
        schedule: [
          for (final s in (j['schedule'] as List?) ?? const [])
            AcaoInstallment(
              no: _n((s as Map)['installment_no']).toInt(),
              principalDue: _n(s['principal_due']),
              interestDue: _n(s['interest_due']),
              status: '${s['status'] ?? ''}',
              dueDate: _d(s['due_date']),
            ),
        ],
      );
}

// ── Client ────────────────────────────────────────────────────────────────

/// Nchemty's savings & loans platform (acao.nchemty.com). Members are signed
/// in with their live Cyclos session (POST /auth/cyclos-session), so no
/// password is asked again; the platform token is kept in memory only and
/// renewed automatically when it expires.
class AcaoApi {
  AcaoApi(this._session)
      : _dio = Dio(BaseOptions(
          baseUrl: Env.acaoBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        ));

  final Dio _dio;
  final SessionHolder _session;
  String? _token;

  Future<String> _signIn() async {
    final cyclos = _session.token;
    if (cyclos == null) throw ApiException('Please sign in again.', statusCode: 401);
    try {
      final res = await _dio.post<Map<String, dynamic>>('/auth/cyclos-session',
          data: {'sessionToken': cyclos});
      return _token = '${res.data!['token']}';
    } on DioException catch (e) {
      throw _error(e);
    }
  }

  /// Runs [call] with a platform token; on 401 signs in again once.
  Future<T> _authed<T>(Future<T> Function(Options o) call) async {
    final token = _token ?? await _signIn();
    try {
      return await call(Options(headers: {'Authorization': 'Bearer $token'}));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final fresh = await _signIn();
        try {
          return await call(Options(headers: {'Authorization': 'Bearer $fresh'}));
        } on DioException catch (e2) {
          throw _error(e2);
        }
      }
      throw _error(e);
    }
  }

  ApiException _error(DioException e) {
    final data = e.response?.data;
    final msg = data is Map && data['error'] != null ? '${data['error']}' : null;
    if (msg != null) return ApiException(msg, statusCode: e.response?.statusCode);
    if (e.response == null) {
      return ApiException('Could not reach Nchemty savings & loans. Check your connection.');
    }
    return ApiException.fromDio(e);
  }

  /// Forget the platform token (sign-out).
  void reset() => _token = null;

  List<Map<String, dynamic>> _list(Object? d) =>
      [for (final e in (d as List?) ?? const []) (e as Map).cast<String, dynamic>()];

  // Savings
  Future<List<AcaoProduct>> savingsProducts() => _authed((o) async {
        final r = await _dio.get<List<dynamic>>('/savings/products', options: o);
        return _list(r.data).map(AcaoProduct.fromJson).toList();
      });

  Future<List<AcaoSavingsAccount>> savingsAccounts() => _authed((o) async {
        final r = await _dio.get<List<dynamic>>('/savings/accounts', options: o);
        return _list(r.data).map(AcaoSavingsAccount.fromJson).toList();
      });

  /// Returns the application reference.
  Future<String> applySavings({required String productId, required String termCode, String? goal}) =>
      _authed((o) async {
        final r = await _dio.post<Map<String, dynamic>>('/savings/applications',
            data: {
              'productId': productId,
              'termCode': termCode,
              if (goal != null && goal.trim().isNotEmpty) 'savingsGoal': goal.trim(),
            },
            options: o);
        return '${r.data?['reference'] ?? ''}';
      });

  Future<AcaoWithdrawalQuote> withdrawalQuote(String accountId) => _authed((o) async {
        final r = await _dio.get<Map<String, dynamic>>(
            '/savings/accounts/$accountId/early-withdrawal-quote',
            options: o);
        return AcaoWithdrawalQuote.fromJson(r.data!);
      });

  /// Returns the total being paid out.
  Future<num> withdrawEarly(String accountId) => _authed((o) async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/savings/accounts/$accountId/early-withdrawal',
            options: o);
        return _n(r.data?['totalPaid']);
      });

  // Loans
  Future<List<AcaoLoanApplication>> loanApplications() => _authed((o) async {
        final r = await _dio.get<List<dynamic>>('/loans/applications', options: o);
        return _list(r.data).map(AcaoLoanApplication.fromJson).toList();
      });

  Future<List<AcaoLoan>> loans() => _authed((o) async {
        final r = await _dio.get<List<dynamic>>('/loans', options: o);
        return _list(r.data).map(AcaoLoan.fromJson).toList();
      });

  Future<AcaoLoan> loan(String id) => _authed((o) async {
        final r = await _dio.get<Map<String, dynamic>>('/loans/$id', options: o);
        return AcaoLoan.fromJson(r.data!);
      });

  /// Returns the application reference. The rate is set by Nchemty.
  Future<String> applyLoan({required num amount, required int termMonths, required String purpose}) =>
      _authed((o) async {
        final r = await _dio.post<Map<String, dynamic>>('/loans/applications',
            data: {'requestedAmount': amount, 'termMonths': termMonths, 'purpose': purpose.trim()},
            options: o);
        return '${r.data?['reference'] ?? ''}';
      });
}

final acaoApiProvider = Provider<AcaoApi>((ref) => AcaoApi(ref.watch(sessionHolderProvider)));
