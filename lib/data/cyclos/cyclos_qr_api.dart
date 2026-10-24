import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../../core/utils/money.dart';
import '../models/models.dart';

/// Native Cyclos 4.16.17 QR payments, per the instance's openapi.json.
///
/// * Easy invoice: a member's own QR (optionally with an amount).
///   Image:   GET  /easy-invoices/qr-code/{to}?amount=&size=
///   Payer:   GET  /easy-invoices/data-for-perform/{to}?amount=
///            POST /easy-invoices/preview   {subject: to, amount, type}
///            POST /easy-invoices           + `confirmationPassword` header
/// * Ticket: a one-off charge created by the receiver (shop, agent).
///   Create:  POST /tickets {amount, description} -> TransactionView
///   Image:   GET  /tickets/{ticket}/qr-code
///   Payer:   GET  /tickets/{ticket}; POST /tickets/{ticket}/preview;
///            POST /tickets/{ticket}/approve + `confirmationPassword` header
class CyclosQrApi {
  CyclosQrApi(this._dio, this._session);
  final Dio _dio;
  final SessionHolder _session;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Headers for Image.network so QR images load with the session,
  /// without putting the token in the URL.
  Map<String, String> get imageHeaders => {
        if (_session.token != null) 'Session-Token': _session.token!,
        'Channel': Env.cyclosChannel,
      };

  Options _confirm(String? credential) => Options(headers: {
        if (credential != null) 'confirmationPassword': credential,
      });

  // ---- Easy invoices (member QR) ----

  /// URL of an easy-invoice QR image for [to] (user id or principal).
  String easyInvoiceQrUrl(String to, {num? amount, String? description, int size = 600}) {
    final q = <String, String>{
      'size': '$size',
      if (amount != null && amount > 0) 'amount': amount.toString(),
      if (description != null && description.isNotEmpty) 'description': description,
    };
    return Uri.parse('${Env.cyclosBaseUrl}/easy-invoices/qr-code/'
            '${Uri.encodeComponent(to)}')
        .replace(queryParameters: q)
        .toString();
  }

  /// Payee, fixed amount and payment types for an easy invoice.
  Future<EasyInvoiceData> easyInvoiceData(String to, {num? amount}) =>
      _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/easy-invoices/data-for-perform/${Uri.encodeComponent(to)}',
          queryParameters: {if (amount != null) 'amount': amount.toString()},
        );
        return EasyInvoiceData.fromJson(res.data!);
      });

  Map<String, dynamic> _easyBody(String to, num amount, String? type, String? description) => {
        'subject': to,
        'amount': amount.toString(),
        if (type != null) 'type': type,
        if (description != null && description.isNotEmpty) 'description': description,
      };

  Future<PaymentPreview> previewEasyInvoice(
          {required String to, required num amount, String? type, String? description}) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/easy-invoices/preview',
            data: _easyBody(to, amount, type, description));
        return PaymentPreview.fromJson(res.data!);
      });

  Future<String> payEasyInvoice(
          {required String to,
          required num amount,
          String? type,
          String? description,
          String? confirmationPassword}) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/easy-invoices',
            data: _easyBody(to, amount, type, description),
            options: _confirm(confirmationPassword));
        return (res.data?['transactionNumber'] ?? res.data?['id']).toString();
      });

  // ---- Tickets (merchant / agent QR) ----

  /// Receiver creates an open ticket and shows its QR.
  Future<String> createTicket({required num amount, String? description}) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/tickets', data: {
          'amount': amount.toString(),
          if (description != null && description.isNotEmpty) 'description': description,
        });
        final data = res.data ?? const {};
        return (data['ticketNumber'] ?? data['id']).toString();
      });

  String ticketQrUrl(String ticket, {int size = 600}) =>
      '${Env.cyclosBaseUrl}/tickets/${Uri.encodeComponent(ticket)}/qr-code?size=$size';

  Future<TicketInfo> ticket(String number) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
            '/tickets/${Uri.encodeComponent(number)}');
        return TicketInfo.fromJson(res.data!);
      });

  /// Payer previews the payment the ticket will generate.
  Future<PaymentPreview> previewTicket(String number) => _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            '/tickets/${Uri.encodeComponent(number)}/preview');
        return PaymentPreview.fromJson(res.data ?? const {});
      });

  /// Payer approves; Cyclos checks the confirmation credential if required.
  Future<void> approveTicket(String number, String? confirmationPassword) =>
      _guard(() => _dio.post<void>(
            '/tickets/${Uri.encodeComponent(number)}/approve',
            options: _confirm(confirmationPassword),
          ));

  Future<void> cancelTicket(String number) => _guard(
      () => _dio.post<void>('/tickets/${Uri.encodeComponent(number)}/cancel'));
}

/// GET /easy-invoices/data-for-perform/{to} (Cyclos DataForEasyInvoice).
class EasyInvoiceData {
  EasyInvoiceData({required this.payee, required this.amount, required this.paymentTypes});
  final CyclosUser? payee;
  final num? amount;
  final List<PaymentType> paymentTypes;

  factory EasyInvoiceData.fromJson(Map<String, dynamic> j) {
    final to = (j['to'] as Map?)?.cast<String, dynamic>();
    final types = ((j['paymentTypes'] as List?) ?? const [])
        .map((t) => PaymentType.fromJson((t as Map).cast<String, dynamic>()))
        .toList();
    final selected = (j['paymentTypeData'] as Map?)?.cast<String, dynamic>();
    if (types.isEmpty && selected != null) types.add(PaymentType.fromJson(selected));
    return EasyInvoiceData(
      payee: to == null ? null : CyclosUser.fromJson(to),
      amount: j['amount'] == null ? null : Money.parse(j['amount']),
      paymentTypes: types,
    );
  }
}

class TicketInfo {
  TicketInfo({
    required this.number,
    required this.status,
    required this.amount,
    required this.payeeName,
    this.description,
  });

  final String number;
  final String status; // open | approved | processed | cancelled | expired
  final num amount;
  final String payeeName;
  final String? description;

  bool get isOpen => status.toLowerCase() == 'open';

  factory TicketInfo.fromJson(Map<String, dynamic> j) {
    final toAccount = j['to'] as Map?;
    final to = (j['payee'] as Map?) ??
        (toAccount?['user'] as Map?) ??
        toAccount;
    return TicketInfo(
      number: (j['ticketNumber'] ?? j['id']).toString(),
      status: (j['ticketStatus'] ?? j['status'] ?? '').toString(),
      amount: Money.parse(j['amount']),
      payeeName: (to?['display'] ?? '').toString(),
      description: j['description']?.toString(),
    );
  }
}

/// What a scanned QR asks for.
sealed class ScannedQr {
  const ScannedQr();

  /// Parses the URLs Cyclos encodes. Nchemty's instance uses
  ///   https://ebank.nchemty.com/pay/{32-char code}[?amount=..]
  /// (confirmed from a real QR). Only QR codes for our own Cyclos host are
  /// accepted, so a look-alike domain can't be scanned into a payment.
  static ScannedQr? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    // Not a link: a member identifier or QR token. The official frontend
    // looks these up with the `*:` (any principal type) prefix.
    if (uri == null || !uri.hasScheme) return PrincipalQr(text);
    if (uri.scheme != 'https') return null;
    final cyclosHost = Uri.parse(Env.cyclosBaseUrl).host;
    if (uri.host.toLowerCase() != cyclosHost.toLowerCase()) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final amountParam = num.tryParse(uri.queryParameters['amount'] ?? '');

    // Native Cyclos pay link: /pay/{code}. Ticket or easy invoice is
    // decided by asking Cyclos (see the payment sheet).
    final payIdx = segs.indexOf('pay');
    if (payIdx >= 0 && payIdx == segs.length - 2) {
      return PayLinkQr(Uri.decodeComponent(segs[payIdx + 1]),
          amount: amountParam,
          description: uri.queryParameters['description']);
    }
    final ticket = uri.queryParameters['ticket'] ??
        _after(segs, const ['ticket', 'tickets']);
    if (ticket != null) return TicketQr(ticket);
    final to = uri.queryParameters['to'] ??
        _after(segs, const ['easy-invoice', 'easyInvoice']);
    if (to != null) {
      return EasyInvoiceQr(to,
          amount: amountParam, description: uri.queryParameters['description']);
    }
    return null;
  }

  static String? _after(List<String> segs, List<String> markers) {
    for (var i = 0; i < segs.length - 1; i++) {
      if (markers.contains(segs[i])) return Uri.decodeComponent(segs[i + 1]);
    }
    return null;
  }
}

/// A raw identifier (username, phone, account number or QR token).
class PrincipalQr extends ScannedQr {
  const PrincipalQr(this.value);
  final String value;
}

/// `/pay/{code}` before Cyclos has told us whether it is a ticket.
class PayLinkQr extends ScannedQr {
  const PayLinkQr(this.code, {this.amount, this.description});
  final String code;
  final num? amount;
  final String? description;
}

class TicketQr extends ScannedQr {
  const TicketQr(this.number);
  final String number;
}

class EasyInvoiceQr extends ScannedQr {
  const EasyInvoiceQr(this.to, {this.amount, this.description});
  final String to;
  final num? amount;
  final String? description;
}

final cyclosQrApiProvider = Provider<CyclosQrApi>((ref) =>
    CyclosQrApi(ref.watch(cyclosDioProvider), ref.watch(sessionHolderProvider)));
