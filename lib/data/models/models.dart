import '../../core/utils/money.dart';

/// Hand-written models keep the starter free of build_runner. Move to
/// freezed + json_serializable once the shapes settle.

class CyclosUser {
  CyclosUser({required this.id, required this.display, this.shortDisplay});
  final String id;
  final String display;
  final String? shortDisplay;

  String get initials {
    final parts = display.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  factory CyclosUser.fromJson(Map<String, dynamic> j) => CyclosUser(
        id: j['id'].toString(),
        display: (j['display'] ?? j['name'] ?? '').toString(),
        shortDisplay: j['shortDisplay']?.toString(),
      );
}

class Account {
  Account({
    required this.id,
    required this.typeId,
    required this.typeName,
    required this.number,
    required this.balance,
    required this.available,
  });

  final String id;

  /// Account type internal name (or id) used in history URLs.
  final String typeId;
  final String typeName;
  final String? number;
  final num balance;
  final num available;

  String get maskedNumber {
    final n = number;
    if (n == null || n.length < 4) return '';
    return '•••• ${n.substring(n.length - 4)}';
  }

  /// Cyclos AccountWithStatus: {id, number, type:{id, internalName, name},
  /// status:{balance, availableBalance, ...}}
  factory Account.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] as Map?)?.cast<String, dynamic>() ?? const {};
    final status = (j['status'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Account(
      id: j['id'].toString(),
      typeId: (type['internalName'] ?? type['id']).toString(),
      typeName: (type['name'] ?? '').toString(),
      number: j['number']?.toString(),
      balance: Money.parse(status['balance']),
      available: Money.parse(status['availableBalance'] ?? status['balance']),
    );
  }
}

class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.date,
    required this.amount,
    required this.title,
    this.description,
    this.transactionNumber,
  });

  final String id;
  final DateTime date;
  final num amount;
  final String title;
  final String? description;
  final String? transactionNumber;

  bool get isCredit => amount > 0;

  factory HistoryEntry.fromJson(Map<String, dynamic> j) {
    final related = (j['relatedAccount'] as Map?)?.cast<String, dynamic>();
    final relatedUser = (related?['user'] as Map?)?.cast<String, dynamic>();
    final type = (j['type'] as Map?)?.cast<String, dynamic>();
    final title = relatedUser?['display'] ??
        (related?['type'] as Map?)?['name'] ??
        type?['name'] ??
        'Transaction';
    return HistoryEntry(
      id: j['id'].toString(),
      date: DateTime.tryParse(j['date']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      amount: Money.parse(j['amount']),
      title: title.toString(),
      description: j['description']?.toString(),
      transactionNumber: j['transactionNumber']?.toString(),
    );
  }
}

class HistoryPage {
  HistoryPage(this.items, {required this.hasNext});
  final List<HistoryEntry> items;
  final bool hasNext;
}

/// A payment type the member may use (Cyclos TransferTypeWithCurrency).
class PaymentType {
  PaymentType({required this.id, required this.name, required this.fromType});
  final String id; // id or qualified internal name, sent as `type`
  final String name;
  final String? fromType; // source account type internal name

  factory PaymentType.fromJson(Map<String, dynamic> j) {
    final from = (j['from'] as Map?)?.cast<String, dynamic>();
    final fromName = (from?['internalName'] ?? from?['id'])?.toString();
    final internal = j['internalName']?.toString();
    return PaymentType(
      id: internal != null && fromName != null
          ? '$fromName.$internal'
          : j['id'].toString(),
      name: (j['name'] ?? internal ?? '').toString(),
      fromType: fromName,
    );
  }
}

/// GET /self/payments/data-for-perform?to=… (Cyclos DataForTransaction).
class PaymentData {
  PaymentData({required this.payee, required this.paymentTypes});
  final CyclosUser? payee;
  final List<PaymentType> paymentTypes;

  factory PaymentData.fromJson(Map<String, dynamic> j) {
    final to = (j['toUser'] as Map?)?.cast<String, dynamic>();
    final types = (j['paymentTypes'] as List?) ?? const [];
    final selected = (j['paymentTypeData'] as Map?)?.cast<String, dynamic>();
    final list = types
        .map((t) => PaymentType.fromJson((t as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty && selected != null) {
      list.add(PaymentType.fromJson(selected));
    }
    return PaymentData(
      payee: to == null ? null : CyclosUser.fromJson(to),
      paymentTypes: list,
    );
  }
}

/// How Cyclos wants this action confirmed (Cyclos PasswordInput).
class ConfirmationInput {
  ConfirmationInput({
    required this.label,
    required this.isOtp,
    required this.numeric,
    required this.otpMediums,
    required this.usable,
  });

  final String label;
  final bool isOtp;
  final bool numeric;
  final List<String> otpMediums; // sms, email

  /// False when only device/PIN/TOTP confirmation is allowed, which this
  /// app version cannot provide yet.
  final bool usable;

  static ConfirmationInput? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final allowed = ((j['allowedCredentials'] as List?) ?? const ['password'])
        .map((e) => e.toString())
        .toList();
    final pt = (j['passwordType'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ConfirmationInput(
      label: (pt['name'] ?? 'Transaction password').toString(),
      isOtp: pt['mode'] == 'otp',
      numeric: pt['onlyNumeric'] == true,
      otpMediums: ((j['otpSendMediums'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      usable: allowed.contains('password'),
    );
  }
}

class PaymentPreview {
  PaymentPreview({
    required this.amount,
    required this.totalAmount,
    required this.fees,
    required this.recipient,
    required this.confirmation,
    this.confirmationMessage,
    this.paymentTypeName,
  });

  final num amount;
  final num totalAmount;
  final num fees;
  final String recipient;
  final ConfirmationInput? confirmation;
  final String? confirmationMessage;
  final String? paymentTypeName;

  bool get requiresConfirmation => confirmation != null;

  factory PaymentPreview.fromJson(Map<String, dynamic> j) {
    final payment = (j['payment'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fees = (j['fees'] as List?) ?? const [];
    final feeSum = fees.fold<num>(
        0, (sum, f) => sum + Money.parse((f as Map)['amount']));
    final toAccount = (j['toAccount'] as Map?)?.cast<String, dynamic>();
    final toUser = (toAccount?['user'] as Map?) ?? (j['to'] as Map?);
    final amount = Money.parse(j['mainAmount'] ?? payment['amount']);
    return PaymentPreview(
      amount: amount,
      totalAmount: j['totalAmount'] == null ? amount + feeSum : Money.parse(j['totalAmount']),
      fees: feeSum,
      recipient: (toUser?['display'] ?? payment['subject'] ?? '').toString(),
      confirmation: ConfirmationInput.fromJson(j['confirmationPasswordInput']),
      confirmationMessage: j['confirmationMessage']?.toString(),
      paymentTypeName: (j['paymentType'] as Map?)?['name']?.toString(),
    );
  }
}

/// Middleware /v1 quote for cash-out (fee rules live server-side).
class CashoutQuote {
  CashoutQuote({
    required this.quoteId,
    required this.amount,
    required this.fee,
    required this.total,
    required this.expiresAt,
  });

  final String quoteId;
  final num amount;
  final num fee;
  final num total;
  final DateTime expiresAt;

  factory CashoutQuote.fromJson(Map<String, dynamic> j) => CashoutQuote(
        quoteId: j['quoteId'].toString(),
        amount: Money.parse(j['amount']),
        fee: Money.parse(j['fee']),
        total: Money.parse(j['total']),
        expiresAt: DateTime.parse(j['expiresAt'].toString()),
      );
}

enum MomoStatus { pending, successful, failed }

class MomoRequest {
  MomoRequest({required this.id, required this.status, this.message});
  final String id;
  final MomoStatus status;
  final String? message;

  factory MomoRequest.fromJson(Map<String, dynamic> j) => MomoRequest(
        id: j['id'].toString(),
        status: switch (j['status']?.toString().toUpperCase()) {
          'SUCCESSFUL' => MomoStatus.successful,
          'FAILED' || 'REJECTED' || 'TIMEOUT' => MomoStatus.failed,
          _ => MomoStatus.pending,
        },
        message: j['message']?.toString(),
      );
}

class Loan {
  Loan({
    required this.id,
    required this.reference,
    required this.principal,
    required this.outstanding,
    required this.status,
    this.nextDueDate,
    this.nextDueAmount,
  });

  final String id;
  final String reference;
  final num principal;
  final num outstanding;
  final String status;
  final DateTime? nextDueDate;
  final num? nextDueAmount;

  double get progress =>
      principal <= 0 ? 0 : (1 - outstanding / principal).clamp(0, 1).toDouble();

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
        id: j['id'].toString(),
        reference: (j['reference'] ?? '').toString(),
        principal: Money.parse(j['principal']),
        outstanding: Money.parse(j['outstanding']),
        status: (j['status'] ?? '').toString(),
        nextDueDate: DateTime.tryParse(j['nextDueDate']?.toString() ?? ''),
        nextDueAmount:
            j['nextDueAmount'] == null ? null : Money.parse(j['nextDueAmount']),
      );
}

class SavingsProduct {
  SavingsProduct({
    required this.code,
    required this.name,
    required this.summary,
    required this.subscribed,
    this.balance,
  });

  final String code;
  final String name;
  final String summary;
  final bool subscribed;
  final num? balance;

  factory SavingsProduct.fromJson(Map<String, dynamic> j) => SavingsProduct(
        code: j['code'].toString(),
        name: (j['name'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
        subscribed: j['subscribed'] == true,
        balance: j['balance'] == null ? null : Money.parse(j['balance']),
      );
}
