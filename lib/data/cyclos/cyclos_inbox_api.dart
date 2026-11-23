import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../../core/utils/money.dart';
import '../models/models.dart';

/// One Cyclos notification (GET /notifications).
class InboxNotification {
  InboxNotification({
    required this.id,
    required this.date,
    required this.subject,
    required this.message,
    required this.read,
    this.type,
    this.entityType,
    this.entityId,
  });

  final String id;
  final DateTime date;
  final String subject;
  final String message;
  bool read;
  final String? type;
  final String? entityType;
  final String? entityId;

  bool get isPaymentRequest =>
      type == 'paymentRequestReceived' || type == 'paymentRequestExpirationDateChanged';

  factory InboxNotification.fromJson(Map<String, dynamic> j) => InboxNotification(
        id: '${j['id']}',
        date: DateTime.tryParse('${j['date']}')?.toLocal() ?? DateTime.now(),
        subject: '${j['subject'] ?? ''}',
        message: '${j['message'] ?? ''}',
        read: j['read'] == true,
        type: j['type'] as String?,
        entityType: j['entityType'] as String?,
        entityId: j['entityId']?.toString(),
      );
}

/// An open payment request someone sent to this member (they are the payer).
class IncomingPaymentRequest {
  IncomingPaymentRequest({
    required this.id,
    required this.date,
    required this.amount,
    required this.from,
    this.transactionNumber,
    this.description,
    this.expires,
  });

  final String id;
  final DateTime date;
  final num amount;
  final String from;
  final String? transactionNumber;
  final String? description;
  final DateTime? expires;

  factory IncomingPaymentRequest.fromJson(Map<String, dynamic> j) {
    final related = (j['related'] as Map?)?.cast<String, dynamic>();
    final user = (related?['user'] as Map?)?.cast<String, dynamic>();
    return IncomingPaymentRequest(
      id: '${j['id']}',
      date: DateTime.tryParse('${j['date']}')?.toLocal() ?? DateTime.now(),
      amount: Money.parse(j['amount']).abs(),
      from: '${j['relatedName'] ?? user?['display'] ?? (related?['type'] as Map?)?['name'] ?? 'Nchemty'}',
      transactionNumber: j['transactionNumber'] as String?,
      description: j['description'] as String?,
      expires: DateTime.tryParse('${j['expirationDate']}')?.toLocal(),
    );
  }
}

/// What paying a request would do (POST-free: GET /payment-requests/{key}/preview).
class PaymentRequestPreview {
  PaymentRequestPreview({
    required this.payment,
    required this.from,
    this.description,
    this.expires,
    this.transactionNumber,
  });

  final PaymentPreview payment;
  final String from;
  final String? description;
  final DateTime? expires;
  final String? transactionNumber;

  factory PaymentRequestPreview.fromJson(Map<String, dynamic> j) {
    final req = (j['paymentRequest'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fromAcc = (req['to'] as Map?)?.cast<String, dynamic>();
    final fromUser = (fromAcc?['user'] as Map?)?.cast<String, dynamic>();
    final p = PaymentPreview.fromJson(j);
    return PaymentRequestPreview(
      payment: p,
      // The requester is the payee of the resulting payment.
      from: '${fromUser?['display'] ?? p.recipient}',
      description: req['description'] as String?,
      expires: DateTime.tryParse('${req['expirationDate']}')?.toLocal(),
      transactionNumber: req['transactionNumber'] as String?,
    );
  }
}

class CyclosInboxApi {
  CyclosInboxApi(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /notifications/status: unread count for the bell badge.
  Future<int> unreadCount() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/notifications/status');
        return (res.data?['unreadNotifications'] as num?)?.toInt() ?? 0;
      });

  Future<({List<InboxNotification> items, bool hasNext})> notifications({int page = 0}) =>
      _guard(() async {
        final res = await _dio.get<List<dynamic>>('/notifications',
            queryParameters: {'page': page, 'pageSize': 30, 'skipTotalCount': true});
        return (
          items: [
            for (final e in res.data ?? const [])
              InboxNotification.fromJson((e as Map).cast<String, dynamic>()),
          ],
          hasNext: res.headers.value('X-Has-Next-Page') == 'true',
        );
      });

  Future<void> markRead(List<String> ids) => ids.isEmpty
      ? Future.value()
      : _guard(() => _dio.post<void>('/notifications/mark-as-read',
          queryParameters: {'ids': ids.join(',')}));

  /// Requests waiting for this member to pay (GET /self/transactions,
  /// kind paymentRequest, status open, as payer: direction debit).
  Future<List<IncomingPaymentRequest>> incomingRequests() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/self/transactions', queryParameters: {
          'kinds': 'paymentRequest',
          'paymentRequestStatuses': 'open',
          'direction': 'debit',
          'pageSize': 50,
          'skipTotalCount': true,
        });
        return [
          for (final e in res.data ?? const [])
            IncomingPaymentRequest.fromJson((e as Map).cast<String, dynamic>()),
        ];
      });

  Future<PaymentRequestPreview> previewRequest(String key) => _guard(() async {
        final res = await _dio
            .get<Map<String, dynamic>>('/payment-requests/${Uri.encodeComponent(key)}/preview');
        return PaymentRequestPreview.fromJson(res.data!);
      });

  /// Pays the request. Returns the new payment's key (transaction number or
  /// id), or null when Cyclos scheduled it instead (204).
  Future<String?> acceptRequest(String key, {String? confirmationPassword, String? comments}) =>
      _guard(() async {
        final res = await _dio.post<dynamic>(
          '/payment-requests/${Uri.encodeComponent(key)}/accept',
          data: {if (comments != null && comments.isNotEmpty) 'comments': comments},
          options: Options(headers: {
            if (confirmationPassword != null) 'confirmationPassword': confirmationPassword,
          }),
        );
        final d = res.data;
        if (d is Map) return '${d['transactionNumber'] ?? d['id']}';
        return null;
      });

  Future<void> rejectRequest(String key, {String? confirmationPassword, String? comments}) =>
      _guard(() => _dio.post<void>(
            '/payment-requests/${Uri.encodeComponent(key)}/reject',
            data: comments ?? '',
            options: Options(contentType: 'text/plain', headers: {
              if (confirmationPassword != null) 'confirmationPassword': confirmationPassword,
            }),
          ));
}

final cyclosInboxApiProvider =
    Provider<CyclosInboxApi>((ref) => CyclosInboxApi(ref.watch(cyclosDioProvider)));

/// Unread notifications + open payment requests, for the Home bell.
final inboxBadgeProvider = FutureProvider.autoDispose<({int unread, int requests})>((ref) async {
  final api = ref.watch(cyclosInboxApiProvider);
  // Refresh every minute while Home is open.
  final timer = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  int unread = 0, requests = 0;
  try {
    unread = await api.unreadCount();
  } catch (_) {}
  try {
    requests = (await api.incomingRequests()).length;
  } catch (_) {}
  return (unread: unread, requests: requests);
});

final incomingRequestsProvider = FutureProvider.autoDispose<List<IncomingPaymentRequest>>(
    (ref) => ref.watch(cyclosInboxApiProvider).incomingRequests());
