import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/locations/locations_api.dart';
import '../common/legal_links.dart' show openLegalPage;
import '../common/widgets.dart';

/// Where the phone is, or why we don't know.
sealed class _Fix {
  const _Fix();
}

class _Located extends _Fix {
  const _Located(this.lat, this.lng);
  final double lat;
  final double lng;
}

class _NoFix extends _Fix {
  const _NoFix(this.reason, {this.openSettings = false});
  final String reason;
  final bool openSettings;
}

final _positionProvider = FutureProvider.autoDispose<_Fix>((ref) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const _NoFix('Turn on location to see the agents nearest to you.',
          openSettings: true);
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied) {
      return const _NoFix('Allow location access to see the agents nearest to you.');
    }
    if (p == LocationPermission.deniedForever) {
      return const _NoFix('Location access is off for Nchemty. Allow it in Settings.',
          openSettings: true);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return _Located(pos.latitude, pos.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return _Located(last.latitude, last.longitude);
      return const _NoFix('Could not find your position. Try again outside or near a window.');
    }
  } catch (_) {
    return const _NoFix('Location is not available on this phone.');
  }
});

/// Turn-by-turn navigation in the phone's maps app.
Future<void> navigateTo(BuildContext context, NchemtyLocation l) async {
  final dest = '${l.lat},${l.lng}';
  final tries = <Uri>[
    if (Platform.isAndroid) Uri.parse('google.navigation:q=$dest&mode=d'),
    if (Platform.isIOS) Uri.parse('https://maps.apple.com/?daddr=$dest&dirflg=d'),
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving'),
  ];
  for (final u in tries) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('No maps app found on this phone.')));
  }
}

class FindAgentScreen extends ConsumerStatefulWidget {
  const FindAgentScreen({super.key});

  @override
  ConsumerState<FindAgentScreen> createState() => _FindAgentScreenState();
}

class _FindAgentScreenState extends ConsumerState<FindAgentScreen> {
  String? _service;

  @override
  Widget build(BuildContext context) {
    final s = S.of(ref);
    final places = ref.watch(locationsProvider);
    final fix = ref.watch(_positionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('findAgent')),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.my_location),
            onPressed: () {
              ref.invalidate(_positionProvider);
              ref.invalidate(locationsProvider);
            },
          ),
        ],
      ),
      body: places.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorRetry(error: e, onRetry: () => ref.invalidate(locationsProvider)),
        ),
        data: (all) {
          final here = fix.valueOrNull is _Located ? fix.valueOrNull as _Located : null;
          final services = <String>{for (final p in all) ...p.services}.toList();
          final shown = all
              .where((p) => _service == null || p.services.contains(_service))
              .map((p) => (
                    place: p,
                    metres: here == null ? null : distanceMetres(here.lat, here.lng, p.lat, p.lng),
                  ))
              .toList();
          if (here != null) shown.sort((a, b) => a.metres!.compareTo(b.metres!));
          final nearest = here != null && shown.isNotEmpty ? shown.first : null;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_positionProvider);
              ref.invalidate(locationsProvider);
              await ref.read(locationsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (services.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(s.t('allServices')),
                          selected: _service == null,
                          onSelected: (_) => setState(() => _service = null),
                        ),
                      ),
                      for (final sv in services)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(sv),
                            selected: _service == sv,
                            onSelected: (_) => setState(() => _service = sv),
                          ),
                        ),
                    ]),
                  ),
                const SizedBox(height: 12),
                fix.when(
                  loading: () => const _Banner(
                      icon: Icons.location_searching, text: 'Finding your position…'),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (f) => switch (f) {
                    _NoFix(:final reason, :final openSettings) => _Banner(
                        icon: Icons.location_off_outlined,
                        text: reason,
                        action: TextButton(
                          onPressed: () async {
                            if (openSettings) {
                              await Geolocator.openLocationSettings();
                            }
                            ref.invalidate(_positionProvider);
                          },
                          child: Text(openSettings ? 'Settings' : s.t('retry')),
                        ),
                      ),
                    _Located() => const SizedBox.shrink(),
                  },
                ),
                if (nearest != null) ...[
                  _NearestCard(place: nearest.place, metres: nearest.metres!),
                  const SizedBox(height: 16),
                ],
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No branch or agent offers this service yet.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  ),
                for (final e in shown.skip(nearest == null ? 0 : 1))
                  _PlaceCard(place: e.place, metres: e.metres),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => openLegalPage(context, Env.findUsUrl),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('See all on nchemty.com'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.goldLight,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Icon(icon, color: AppColors.greenDark),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (action != null) action!,
          ]),
        ),
      );
}

class _NearestCard extends StatelessWidget {
  const _NearestCard({required this.place, required this.metres});
  final NchemtyLocation place;
  final double metres;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.green,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nearest ${place.isAgent ? 'agent' : 'branch'} · ${formatDistance(metres)}',
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(place.name,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              if (place.address != null) ...[
                const SizedBox(height: 4),
                Text(place.address!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              ],
              if (place.services.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(place.services.join(' · '),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold, foregroundColor: AppColors.greenDark),
                    onPressed: () => navigateTo(context, place),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Start navigation'),
                  ),
                ),
                if (place.phone != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Call',
                    onPressed: () => _launch('tel:${place.phone}'),
                    icon: const Icon(Icons.call),
                  ),
                ],
              ]),
            ],
          ),
        ),
      );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, this.metres});
  final NchemtyLocation place;
  final double? metres;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(place.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (place.type != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Chip(
                      label: Text(place.type!),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (metres != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 8),
                    child: Text(formatDistance(metres!),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.green)),
                  ),
              ]),
              if (place.address != null)
                Text(place.address!, style: const TextStyle(color: AppColors.muted)),
              if (place.services.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(place.services.join(' · '), style: const TextStyle(fontSize: 13)),
                ),
              Wrap(children: [
                TextButton.icon(
                  onPressed: () => navigateTo(context, place),
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Directions'),
                ),
                if (place.phone != null)
                  TextButton.icon(
                    onPressed: () => _launch('tel:${place.phone}'),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call'),
                  ),
                if (place.whatsapp != null)
                  TextButton.icon(
                    onPressed: () => _launch(place.whatsapp!),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('WhatsApp'),
                  ),
              ]),
            ],
          ),
        ),
      );
}

Future<void> _launch(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}
