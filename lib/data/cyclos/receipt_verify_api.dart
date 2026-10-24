import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/network/api_exception.dart';

/// Answer of the public `verify-receipt/json` custom web service
/// (docs/cyclos/verify-receipt.groovy).
class ReceiptVerification {
  const ReceiptVerification({
    required this.valid,
    required this.reference,
    this.amount,
    this.dateText,
    this.type,
    this.from,
    this.to,
    this.reversed = false,
  });

  final bool valid;
  final String reference;
  final num? amount;
  final String? dateText;
  final String? type;
  final String? from;
  final String? to;
  final bool reversed;

  factory ReceiptVerification.fromJson(Map<String, dynamic> j) => ReceiptVerification(
        valid: j['valid'] == true,
        reference: '${j['reference'] ?? ''}',
        amount: j['amount'] is num ? j['amount'] as num : num.tryParse('${j['amount']}'),
        dateText: j['dateText'] as String?,
        type: j['type'] as String?,
        from: j['from'] as String?,
        to: j['to'] as String?,
        reversed: j['reversed'] == true,
      );
}

/// No session: the service runs as guest, exactly like a phone camera scan.
class ReceiptVerifyApi {
  ReceiptVerifyApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.json,
              headers: {'Accept': 'application/json'},
            ));
  final Dio _dio;

  static Uri jsonUri(String base, String reference, num amount) {
    final u = Uri.parse(base);
    return u.replace(
      pathSegments: [...u.pathSegments.where((s) => s.isNotEmpty), 'json'],
      queryParameters: {'tx': reference, 'a': '${amount.abs().round()}'},
    );
  }

  Future<ReceiptVerification> verify(String reference, num amount) async {
    final base = Env.receiptVerifyUrl;
    if (base.isEmpty) {
      throw ApiException('Receipt verification is turned off in this build.');
    }
    try {
      final res = await _dio.getUri<dynamic>(jsonUri(base, reference.trim(), amount));
      final data = res.data;
      if (data is Map<String, dynamic>) return ReceiptVerification.fromJson(data);
      throw ApiException('The verification service gave an unexpected answer.');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw ApiException(
            'The receipt verification service is not set up on the Nchemty server yet.',
            statusCode: 404);
      }
      throw ApiException.fromDio(e);
    }
  }
}

final receiptVerifyApiProvider = Provider<ReceiptVerifyApi>((_) => ReceiptVerifyApi());
