import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../../core/utils/money.dart';

/// Native Cyclos QR payments (Tickets API). Two flows:
///
/// * Easy invoice: a member's static or amount QR. Cyclos encodes a URL to
///   its payment confirmation page; the payer pays the encoded user.
///   QR image: GET /tickets/easy-invoice-qr-code/{user}?amount=...
/// * Ticket: the receiver (shop, agent) creates a one-off ticket; the payer
///   scans it and approves. POST /tickets -> GET /tickets/{n}/qr-code ->
///   payer GET /tickets/{n} -> POST /tickets/{n}/preview -> /approve.
///
/// Paths are from the Cyclos Tickets API; confirm them against your 4.16.17
/// /api/openapi.yaml (newer versions may expose easy invoices separately).
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

  /// Headers for Image.network so the QR image loads with the session,
  /// without putting the token in the URL.
  Map<String, String> get imageHeaders => {
        if (_session.token != null) 'Session-Token': _session.token!,
        'Channel': Env.cyclosChannel,
      };

  /// URL of the member's easy-invoice QR image. `user` must be a real
  /// identifier (id or username), not `self`: the encoded URL is shared.
  String easyInvoiceQrUrl(String user, {num? amount, String? description}) {
    final q = <String, String>{
      if (amount != null && amount > 0) 'amount': amount.toString(),
      if (description != null && description.isNotEmpty)
        'description': description,
    };
    return Uri.parse('${Env.cyclosBaseUrl}/tickets/easy-invoice-qr-code/'
            '${Uri.encodeComponent(user)}')
        .replace(queryParameters: q.isEmpty ? null : q)
        .toString();
  }

  // ---- Tickets (merchant / agent QR) ----

  /// Receiver creates an open ticket and shows its QR.
  Future<String> createTicket({required num amount, String? description}) =>
      _guard(() async {
        final res = await _dio.post<dynamic>('/tickets', data: {
          'amount': amount.toString(),
          if (description != null && description.isNotEmpty)
            'description': description,
        });
        final data = res.data;
        // Cyclos answers with the ticket number (string) or an object.
        if (data is Map) return (data['ticketNumber'] ?? data['id']).toString();
        return data.toString().replaceAll('"', '');
      });

  String ticketQrUrl(String ticket) =>
      '${Env.cyclosBaseUrl}/tickets/${Uri.encodeComponent(ticket)}/qr-code';

  Future<TicketInfo> ticket(String number) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/tickets/$number');
        return TicketInfo.fromJson(res.data!);
      });

  /// Payer previews the payment the ticket will generate (shows fees).
  Future<Map<String, dynamic>> previewTicket(String number) => _guard(() async {
        final res =
            await _dio.post<Map<String, dynamic>>('/tickets/$number/preview');
        return res.data ?? const {};
      });

  /// Payer approves; Cyclos checks the confirmation password.
  Future<void> approveTicket(String number, String confirmationPassword) =>
      _guard(() => _dio.post<void>(
            '/tickets/$number/approve',
            options: Options(
                headers: {'Confirmation-Password': confirmationPassword}),
          ));

  Future<void> cancelTicket(String number) =>
      _guard(() => _dio.post<void>('/tickets/$number/cancel'));
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
    final to = (j['to'] as Map?) ?? (j['owner'] as Map?);
    return TicketInfo(
      number: (j['ticketNumber'] ?? j['id']).toString(),
      status: (j['status'] ?? '').toString(),
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
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https') return null;
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
