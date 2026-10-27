/// Build-time configuration. Pass values with --dart-define, e.g.
///   flutter run --dart-define=FLAVOR=dev \
///     --dart-define=CYCLOS_URL=https://ebank-test.nchemty.com/api \
///     --dart-define=HUB_URL=https://brg1-test.nchemty.com/v1
class Env {
  Env._();

  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  /// Cyclos REST base, ending in /api (no trailing slash).
  static const cyclosBaseUrl = String.fromEnvironment(
    'CYCLOS_URL',
    defaultValue: 'https://ebank.nchemty.com/api',
  );

  /// Node middleware / Payment Hub base, ending in /v1.
  static const hubBaseUrl = String.fromEnvironment(
    'HUB_URL',
    defaultValue: 'https://brg1.nchemty.com/v1',
  );

  /// Cyclos channel internal name used for mobile sessions.
  static const cyclosChannel =
      String.fromEnvironment('CYCLOS_CHANNEL', defaultValue: 'mobile');

  /// Internal name of the member's main account type in Cyclos.
  static const mainAccountType =
      String.fromEnvironment('MAIN_ACCOUNT_TYPE', defaultValue: 'member');

  /// Off until the hub's /v1 routes are deployed: loans and savings then
  /// show "coming soon" instead of failing. (MoMo runs on Cyclos custom
  /// operations; Verify ID opens the web KYC wizard, see [kycUrl].)
  /// Turn on with --dart-define=HUB_ENABLED=true.
  static const hubEnabled =
      bool.fromEnvironment('HUB_ENABLED', defaultValue: false);

  /// Internal names of the Cyclos custom operations behind the Top up and
  /// Cash out buttons. Empty = find them by name ("top up", "cash out").
  static const topupOperation = String.fromEnvironment('TOPUP_OPERATION');
  static const cashoutOperation = String.fromEnvironment('CASHOUT_OPERATION');

  static const _receiptVerifyDefine = String.fromEnvironment('RECEIPT_VERIFY_URL');

  /// Public Cyclos custom web service that verifies a receipt
  /// (docs/cyclos/receipt-verification.md). The receipt QR opens
  /// `<url>?tx=<reference>&a=<amount>`. Defaults to
  /// `<Cyclos host>/run/verify-receipt`; `off` disables it.
  static String get receiptVerifyUrl {
    if (_receiptVerifyDefine == 'off') return '';
    if (_receiptVerifyDefine.isNotEmpty) return _receiptVerifyDefine;
    final api = Uri.parse(cyclosBaseUrl);
    final segs = api.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty && segs.last == 'api') segs.removeLast();
    return api.replace(pathSegments: [...segs, 'run', 'verify-receipt']).toString();
  }

  /// Nchemty's web KYC wizard (selfie, liveness, document, OCR, face match).
  /// Verify ID opens it in the in-app browser. Empty: Verify ID says it is
  /// not available yet. Set with --dart-define=KYC_URL=https://...
  static const kycUrl = String.fromEnvironment('KYC_URL');

  /// Legal pages linked from sign-in and the menu (store requirement).
  /// Override with --dart-define=TERMS_URL=... etc. if the addresses differ.
  static const termsUrl =
      String.fromEnvironment('TERMS_URL', defaultValue: 'https://nchemty.com/terms');
  static const privacyUrl =
      String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://nchemty.com/privacy');
  static const accountClosureUrl = String.fromEnvironment('ACCOUNT_CLOSURE_URL',
      defaultValue: 'https://nchemty.com/account-closure');

  static const idleLockAfter = Duration(minutes: 5);
  static const backgroundLockAfter = Duration(seconds: 60);

  static bool get isProd => flavor == 'prod';
}
