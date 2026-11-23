import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/network/api_exception.dart';
import '../cyclos/cyclos_operations_api.dart' show htmlToText;

/// A Nchemty branch or agent, as listed on nchemty.com/find-us.
class NchemtyLocation {
  const NchemtyLocation({
    required this.name,
    required this.lat,
    required this.lng,
    this.type,
    this.address,
    this.services = const [],
    this.phone,
    this.whatsapp,
  });

  final String name;
  final double lat;
  final double lng;

  /// "Branch" or "Agent".
  final String? type;
  final String? address;
  final List<String> services;
  final String? phone;
  final String? whatsapp;

  bool get isAgent => type?.toLowerCase() == 'agent';

  /// JSON shape for the optional endpoint (see docs/find-us-json.md).
  factory NchemtyLocation.fromJson(Map<String, dynamic> j) {
    double num_(Object? v) => v is num ? v.toDouble() : double.parse('$v');
    final services = j['services'];
    return NchemtyLocation(
      name: '${j['name']}',
      lat: num_(j['lat'] ?? j['latitude']),
      lng: num_(j['lng'] ?? j['longitude']),
      type: j['type'] as String?,
      address: (j['address'] ??
              [j['town'], j['landmark']].where((e) => e != null && '$e'.isNotEmpty).join(' · '))
          as String?,
      services: services is List
          ? services.map((e) => '$e').toList()
          : services is String
              ? services.split(RegExp(r'\s*[·,]\s*')).where((e) => e.isNotEmpty).toList()
              : const [],
      phone: j['phone'] as String?,
      whatsapp: j['whatsapp'] as String?,
    );
  }
}

/// Great-circle distance in metres.
double distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

String formatDistance(double metres) => metres < 1000
    ? '${(metres / 10).round() * 10} m'
    : '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} km';

// Coordinates inside a maps link: query=4.15,9.24 / destination= / q= / daddr= / @4.15,9.24
final _coordRe = RegExp(
    r'''href=["'][^"']*?(?:query=|destination=|daddr=|[?&]q=|@)(-?\d{1,2}\.\d+)(?:,|%2C)\s*(-?\d{1,3}\.\d+)[^"']*["']''',
    caseSensitive: false);
final _telRe = RegExp(r'''href=["']tel:([^"']+)["']''', caseSensitive: false);
final _waRe = RegExp(r'''href=["'](https?://(?:wa\.me|api\.whatsapp\.com)/[^"']+)["']''',
    caseSensitive: false);
final _nameRe = RegExp(r'<(h[1-6]|strong|b)\b[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true);
final _serviceWords = RegExp(
    r'cash|loan|account|bill|deposit|withdraw|retrait|dépôt|prêt|compte|facture|ouverture',
    caseSensitive: false);

/// Reads the cards of nchemty.com/find-us: every "Directions" link carries
/// the place's coordinates; the card's name, type, address, services, phone
/// and WhatsApp come from the HTML just before it.
List<NchemtyLocation> parseFindUsHtml(String html) {
  final out = <NchemtyLocation>[];
  final body = html.replaceAll(
      RegExp(r'<(script|style|head)\b[^>]*>.*?</\1\s*>', caseSensitive: false, dotAll: true), '');
  var start = 0;
  for (final m in _coordRe.allMatches(body)) {
    final lat = double.parse(m.group(1)!);
    final lng = double.parse(m.group(2)!);
    final seg = body.substring(start, m.start);
    start = m.end;

    String? name;
    for (final n in _nameRe.allMatches(seg)) {
      final t = htmlToText(n.group(2) ?? '').replaceAll('\n', ' ').trim();
      if (t.isNotEmpty && !RegExp(r'^(branch|agent|agence)$', caseSensitive: false).hasMatch(t)) {
        name = t;
      }
    }
    final lines = htmlToText(seg)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    name ??= lines.isNotEmpty ? lines.first : 'Nchemty';
    final typeMatch =
        RegExp(r'\b(Branch|Agent|Agence)\b', caseSensitive: false).firstMatch(htmlToText(seg));
    final dotted = lines.where((l) => l.contains('·') && l != name).toList();
    final servicesLine = dotted.where(_serviceWords.hasMatch).lastOrNull;
    final addressLine = dotted.where((l) => l != servicesLine).firstOrNull;
    final tel = _telRe.allMatches(seg).lastOrNull?.group(1);
    final wa = _waRe.allMatches(seg).lastOrNull?.group(1);

    out.add(NchemtyLocation(
      name: name.replaceAll(RegExp(r'\s+(Branch|Agent)$', caseSensitive: false), '').trim(),
      lat: lat,
      lng: lng,
      type: typeMatch == null
          ? null
          : '${typeMatch.group(1)![0].toUpperCase()}${typeMatch.group(1)!.substring(1).toLowerCase()}',
      address: addressLine,
      services: servicesLine == null
          ? const []
          : servicesLine.split(RegExp(r'\s*·\s*')).where((s) => s.isNotEmpty).toList(),
      phone: tel == null ? null : Uri.decodeComponent(tel),
      whatsapp: wa,
    ));
  }
  return out;
}

/// Branches and agents: the JSON endpoint when the website offers one,
/// otherwise the find-us page itself.
class LocationsApi {
  LocationsApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));
  final Dio _dio;

  Future<List<NchemtyLocation>> fetch() async {
    if (Env.locationsJsonUrl.isNotEmpty) {
      try {
        final res = await _dio.get<dynamic>(Env.locationsJsonUrl,
            options: Options(responseType: ResponseType.json, headers: {'Accept': 'application/json'}));
        final data = res.data is Map ? (res.data as Map)['locations'] : res.data;
        if (data is List && data.isNotEmpty) {
          return [
            for (final e in data)
              if (e is Map) NchemtyLocation.fromJson(e.cast<String, dynamic>()),
          ];
        }
      } on DioException catch (_) {
        // No JSON endpoint (yet): fall back to the page.
      } on FormatException catch (_) {}
    }
    try {
      final res = await _dio.get<String>(Env.findUsUrl,
          options: Options(responseType: ResponseType.plain));
      final list = parseFindUsHtml(res.data ?? '');
      if (list.isEmpty) {
        throw ApiException('No branches or agents found. Try again later.');
      }
      return list;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final locationsApiProvider = Provider<LocationsApi>((_) => LocationsApi());
final locationsProvider =
    FutureProvider.autoDispose<List<NchemtyLocation>>((ref) => ref.watch(locationsApiProvider).fetch());
