import 'dart:typed_data';

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
      final code = e.response?.statusCode;
      if (code == 404 || code == 405) {
        // The server does not have the mobile sign-in endpoint yet.
        throw ApiException(
            'Savings & loans is not connected yet. The ACAO server needs its mobile sign-in update.',
            statusCode: code);
      }
      if (code == 403) {
        throw ApiException(
            'Savings & loans is not set up for e-banking sign-in yet (the ACAO server must use AUTH_MODE=cyclos).',
            statusCode: code);
      }
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

// ── Shares ────────────────────────────────────────────────────────────────

class AcaoShareClass {
  const AcaoShareClass({
    required this.code,
    required this.name,
    required this.kind,
    required this.price,
    required this.priceMode,
    required this.minUnits,
    required this.active,
    this.maxUnits,
    this.available,
    this.redeemable = true,
    this.transferable = false,
  });
  final String code;
  final String name;

  /// membership / investment
  final String kind;
  final num price;
  final String priceMode;
  final int minUnits;
  final int? maxUnits;

  /// Shares still available to issue (null = unlimited).
  final int? available;
  final bool active;
  final bool redeemable;
  final bool transferable;

  factory AcaoShareClass.fromJson(Map<String, dynamic> j) => AcaoShareClass(
        code: '${j['code']}',
        name: '${j['name'] ?? j['code']}',
        kind: '${j['kind'] ?? ''}',
        price: _n(j['price'] ?? j['nominalValue']),
        priceMode: '${j['priceMode'] ?? 'fixed'}',
        minUnits: _n(j['minUnits']).toInt(),
        maxUnits: _nOrNull(j['maxUnits'])?.toInt(),
        available: _nOrNull(j['available'])?.toInt(),
        active: j['active'] != false,
        redeemable: j['redeemable'] != false,
        transferable: j['transferable'] == true,
      );
}

class AcaoHolding {
  const AcaoHolding({required this.cls, required this.units, required this.value, required this.paidIn, this.pendingOut = 0});
  final AcaoShareClass cls;
  final int units;
  final num value;
  final num paidIn;
  final int pendingOut;
}

class AcaoShareMovement {
  const AcaoShareMovement({
    required this.classCode,
    required this.kind,
    required this.units,
    required this.amount,
    this.unitPrice,
    this.certificateNo,
    this.date,
  });
  final String classCode;

  /// subscribe / redeem / transfer_in / transfer_out / adjustment
  final String kind;
  final int units;
  final num amount;
  final num? unitPrice;
  final String? certificateNo;
  final String? date;

  String get label => switch (kind) {
        'subscribe' => 'Bought',
        'redeem' => 'Sold back',
        'transfer_in' => 'Bought from a member',
        'transfer_out' => 'Sold to a member',
        'adjustment' => 'Adjustment',
        _ => kind,
      };
}

class AcaoShareRequest {
  const AcaoShareRequest({
    required this.reference,
    required this.kind,
    required this.status,
    required this.classCode,
    this.units,
    this.amount,
    this.note,
  });
  final String reference;
  final String kind;
  final String status;
  final String classCode;
  final int? units;
  final num? amount;
  final String? note;

  String get kindLabel => switch (kind) {
        'subscribe' => 'Buy',
        'redeem' => 'Sell back',
        'transfer' => 'Sell to a member',
        'topup' => 'Put towards shares',
        'wallet_refund' => 'Take back from wallet',
        _ => kind,
      };

  String get statusLabel => switch (status) {
        'requested' => 'Waiting for approval',
        'awaiting_buyer' => 'Waiting for the buyer',
        'executed' => 'Done',
        'rejected' => 'Refused',
        'cancelled' => 'Cancelled',
        _ => status,
      };
}

class AcaoDividend {
  const AcaoDividend({
    required this.reference,
    required this.classCode,
    required this.gross,
    required this.tax,
    required this.net,
    this.periodStart,
    this.periodEnd,
    this.status,
  });
  final String reference;
  final String classCode;
  final num gross;
  final num tax;
  final num net;
  final String? periodStart;
  final String? periodEnd;
  final String? status;
}

class AcaoShareStatement {
  const AcaoShareStatement({
    required this.holdings,
    required this.wallet,
    required this.movements,
    required this.requests,
    required this.dividends,
  });
  final List<AcaoHolding> holdings;

  /// classCode → money waiting to become whole shares.
  final Map<String, num> wallet;
  final List<AcaoShareMovement> movements;
  final List<AcaoShareRequest> requests;
  final List<AcaoDividend> dividends;

  num get totalValue => holdings.fold<num>(0, (t, h) => t + h.value);

  factory AcaoShareStatement.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String k) =>
        [for (final e in (j[k] as List?) ?? const []) (e as Map).cast<String, dynamic>()];
    return AcaoShareStatement(
      holdings: [
        for (final h in l('holdings'))
          AcaoHolding(
            cls: AcaoShareClass.fromJson(h),
            units: _n(h['units']).toInt(),
            value: _n(h['value']),
            paidIn: _n(h['paidIn']),
            pendingOut: _n(h['pendingOut']).toInt(),
          ),
      ],
      wallet: {for (final w in l('wallet')) '${w['classCode']}': _n(w['balance'])},
      movements: [
        for (final m in l('movements'))
          AcaoShareMovement(
            classCode: '${m['classCode']}',
            kind: '${m['kind']}',
            units: _n(m['units']).toInt(),
            amount: _n(m['amount']),
            unitPrice: _nOrNull(m['unitPrice']),
            certificateNo: m['certificateNo'] as String?,
            date: m['date'] as String?,
          ),
      ],
      requests: [
        for (final r in l('requests'))
          if (r['mine'] != false)
            AcaoShareRequest(
              reference: '${r['reference'] ?? ''}',
              kind: '${r['kind']}',
              status: '${r['status']}',
              classCode: '${r['classCode']}',
              units: _nOrNull(r['units'])?.toInt(),
              amount: _nOrNull(r['amount']),
              note: (r['decisionNote'] ?? r['reason']) as String?,
            ),
      ],
      dividends: [
        for (final d in l('dividends'))
          AcaoDividend(
            reference: '${d['reference'] ?? ''}',
            classCode: '${d['classCode']}',
            gross: _n(d['gross']),
            tax: _n(d['tax']),
            net: _n(d['net']),
            periodStart: d['periodStart'] as String?,
            periodEnd: d['periodEnd'] as String?,
            status: d['status'] as String?,
          ),
      ],
    );
  }
}

// ── Investments ───────────────────────────────────────────────────────────

class AcaoInvestmentProduct {
  const AcaoInvestmentProduct({
    required this.code,
    required this.name,
    required this.termMonths,
    required this.ratePa,
    required this.minAmount,
    this.maxAmount,
    this.description,
    this.payout,
    this.earlyExit = false,
    this.penaltyPct = 0,
    this.closesOn,
  });
  final String code;
  final String name;
  final int termMonths;
  final num ratePa;
  final num minAmount;
  final num? maxAmount;
  final String? description;

  /// e.g. monthly / quarterly / at_maturity
  final String? payout;
  final bool earlyExit;
  final num penaltyPct;
  final String? closesOn;

  String get payoutLabel => switch (payout) {
        'monthly' => 'Interest paid monthly',
        'quarterly' => 'Interest paid quarterly',
        'annually' || 'yearly' => 'Interest paid yearly',
        'maturity' || 'at_maturity' => 'Interest paid at maturity',
        null => '',
        _ => 'Interest paid ${payout!.replaceAll('_', ' ')}',
      };

  factory AcaoInvestmentProduct.fromJson(Map<String, dynamic> j) => AcaoInvestmentProduct(
        code: '${j['code']}',
        name: '${j['name'] ?? j['code']}',
        termMonths: _n(j['termMonths']).toInt(),
        ratePa: _n(j['ratePa']),
        minAmount: _n(j['minAmount']),
        maxAmount: _nOrNull(j['maxAmount']),
        description: j['description'] as String?,
        payout: j['payout'] as String?,
        earlyExit: j['earlyExit'] == true,
        penaltyPct: _n(j['penaltyPct']),
        closesOn: j['closesOn'] as String?,
      );
}

class AcaoInvestmentPayment {
  const AcaoInvestmentPayment({required this.kind, required this.amount, required this.status, this.dueOn});
  final String kind;
  final num amount;
  final String status;
  final String? dueOn;
}

class AcaoInvestment {
  const AcaoInvestment({
    required this.id,
    required this.reference,
    required this.productName,
    required this.amount,
    required this.status,
    this.ratePa,
    this.termMonths,
    this.startDate,
    this.maturityDate,
    this.exitRequested = false,
    this.earlyExit = false,
    this.note,
    this.payments = const [],
  });
  final String id;
  final String reference;
  final String productName;
  final num amount;

  /// requested / active / matured / closed / rejected / cancelled
  final String status;
  final num? ratePa;
  final int? termMonths;
  final String? startDate;
  final String? maturityDate;
  final bool exitRequested;
  final bool earlyExit;
  final String? note;
  final List<AcaoInvestmentPayment> payments;

  num get interestPaid =>
      payments.where((p) => p.kind == 'interest' && p.status == 'paid').fold<num>(0, (t, p) => t + p.amount);

  factory AcaoInvestment.fromJson(Map<String, dynamic> j) => AcaoInvestment(
        id: '${j['id']}',
        reference: '${j['reference'] ?? ''}',
        productName: '${j['productName'] ?? j['productCode'] ?? 'Investment'}',
        amount: _n(j['amount']),
        status: '${j['status'] ?? ''}',
        ratePa: _nOrNull(j['ratePa']),
        termMonths: _nOrNull(j['termMonths'])?.toInt(),
        startDate: j['startDate'] as String?,
        maturityDate: j['maturityDate'] as String?,
        exitRequested: j['exitRequested'] == true,
        earlyExit: j['earlyExit'] == true,
        note: j['decisionNote'] as String?,
        payments: [
          for (final p in (j['payments'] as List?) ?? const [])
            AcaoInvestmentPayment(
              kind: '${(p as Map)['kind']}',
              amount: _n(p['amount']),
              status: '${p['status'] ?? ''}',
              dueOn: p['dueOn'] as String?,
            ),
        ],
      );
}

extension AcaoSharesInvestments on AcaoApi {
  Future<List<AcaoShareClass>> shareClasses() => _authed((o) async {
        final r = await _dio.get<List<dynamic>>('/shares/classes', options: o);
        return _list(r.data).map(AcaoShareClass.fromJson).toList();
      });

  Future<AcaoShareStatement> myShares() => _authed((o) async {
        final r = await _dio.get<Map<String, dynamic>>('/shares/me', options: o);
        return AcaoShareStatement.fromJson(r.data!);
      });

  /// Asks to buy [units] shares; approved by staff, then paid from the account.
  Future<String> buyShares(String classCode, int units) => _authed((o) async {
        final r = await _dio.post<Map<String, dynamic>>('/shares/subscribe',
            data: {'classCode': classCode, 'units': units}, options: o);
        return '${r.data?['reference'] ?? ''}';
      });

  /// Puts an amount towards shares (share wallet): becomes shares when it can.
  Future<String> topUpShares(String classCode, num amount) => _authed((o) async {
        final r = await _dio.post<Map<String, dynamic>>('/shares/topup',
            data: {'classCode': classCode, 'amount': amount}, options: o);
        return '${r.data?['reference'] ?? ''}';
      });

  /// Share certificate PDF (issued for each purchase).
  Future<Uint8List> shareCertificate(String certificateNo) => _authed((o) async {
        final r = await _dio.get<List<int>>(
          '/shares/certificates/${Uri.encodeComponent(certificateNo)}',
          options: o.copyWith(responseType: ResponseType.bytes, headers: {
            ...?o.headers,
            'Accept': 'application/pdf',
          }),
        );
        return Uint8List.fromList(r.data ?? const []);
      });

  Future<List<AcaoInvestmentProduct>> investmentProducts() => _authed((o) async {
        final r = await _dio.get<List<dynamic>>('/investments/products', options: o);
        return _list(r.data).map(AcaoInvestmentProduct.fromJson).toList();
      });

  Future<List<AcaoInvestment>> myInvestments() => _authed((o) async {
        final r = await _dio.get<List<dynamic>>('/investments/me', options: o);
        return _list(r.data).map(AcaoInvestment.fromJson).toList();
      });

  Future<String> invest(String productCode, num amount) => _authed((o) async {
        final r = await _dio.post<Map<String, dynamic>>('/investments/subscribe',
            data: {'productCode': productCode, 'amount': amount}, options: o);
        return '${r.data?['reference'] ?? ''}';
      });

  Future<void> cancelInvestment(String id) => _authed((o) async {
        await _dio.post<void>('/investments/${Uri.encodeComponent(id)}/cancel', options: o);
      });

  /// Asks to close early. Returns what leaving pays: capital, unpaid
  /// interest, what is forfeited, total.
  Future<({num capital, num interest, num forfeited, num total})> exitInvestment(String id) =>
      _authed((o) async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/investments/${Uri.encodeComponent(id)}/exit',
            options: o);
        final d = r.data ?? const {};
        return (
          capital: _n(d['capital']),
          interest: _n(d['interestUnpaid']),
          forfeited: _n(d['forfeited']),
          total: _n(d['total']),
        );
      });
}
