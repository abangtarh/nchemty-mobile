import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/l10n/strings.dart';

/// Opens a legal page (terms, privacy, account closure) in the in-app
/// browser. Required by Google Play and the App Store: the policies and the
/// account-closure path must be reachable from inside the app.
Future<void> openLegalPage(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null && uri.scheme == 'https') {
    ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView) ||
        await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

/// Footer for the sign-in screen: consent line, policy links and the
/// account-closure link.
class LegalFooter extends ConsumerWidget {
  const LegalFooter({super.key, this.onDark = true});
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(ref);
    final color = onDark ? Colors.white : Theme.of(context).colorScheme.primary;
    final muted = onDark ? Colors.white.withValues(alpha: 0.75) : Colors.black54;

    Widget link(String label, String url) => TextButton(
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(48, 40),
            textStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
          ),
          onPressed: () => openLegalPage(context, url),
          child: Text(label),
        );

    return Column(
      children: [
        Text(s.t('legalConsent'),
            textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12.5)),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            link(s.t('termsLink'), Env.termsUrl),
            link(s.t('privacyLink'), Env.privacyUrl),
            link(s.t('closeAccountLink'), Env.accountClosureUrl),
          ],
        ),
      ],
    );
  }
}
