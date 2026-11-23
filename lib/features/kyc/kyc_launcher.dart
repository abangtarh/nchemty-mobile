import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../common/widgets.dart';

/// Verify ID: opens Nchemty's web KYC wizard (selfie, liveness, document
/// capture, OCR, face match) in the in-app browser (Chrome Custom Tab /
/// Safari view), which handles camera access for liveness itself.
Future<void> openKycWizard(BuildContext context, String title) async {
  final uri = Uri.tryParse(Env.kycUrl);
  if (Env.kycUrl.isEmpty || uri == null || uri.scheme != 'https') {
    await showComingSoon(context, title);
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  if (!ok && context.mounted) {
    // No Custom Tabs provider on this phone: fall back to the browser.
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the verification page.')));
    }
  }
}
