/// Build-time configuration. Pass values with --dart-define, e.g.
///   flutter run --dart-define=FLAVOR=dev \
///     --dart-define=CYCLOS_URL=https://ebank-test.nchemty.com/api \
class Env {
  Env._();

  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  /// Cyclos REST base, ending in /api (no trailing slash).
  static const cyclosBaseUrl = String.fromEnvironment(
    'CYCLOS_URL',
    defaultValue: 'https://ebank.nchemty.com/api',
  );

  /// Nchemty savings & loans platform (ACAO), ending in /api.
  static const acaoBaseUrl = String.fromEnvironment(
    'ACAO_URL',
    defaultValue: 'https://acao.nchemty.com/api',
  );

  /// Cyclos channel internal name used for mobile sessions.
  static const cyclosChannel =
      String.fromEnvironment('CYCLOS_CHANNEL', defaultValue: 'mobile');

  /// Internal name of the member's main account type in Cyclos.
  static const mainAccountType =
      String.fromEnvironment('MAIN_ACCOUNT_TYPE', defaultValue: 'member');

  /// Internal names of the Cyclos custom operations behind the Top up and
  /// Cash out buttons (the Payment Hub's operations in Cyclos).
  static const topupOperation =
      String.fromEnvironment('TOPUP_OPERATION', defaultValue: 'hubTopup');
  static const cashoutOperation =
      String.fromEnvironment('CASHOUT_OPERATION', defaultValue: 'hubCashout');

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
      String.fromEnvironment('TERMS_URL', defaultValue: 'https://www.nchemty.com/legal/terms');
  static const privacyUrl =
      String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://www.nchemty.com/legal/privacy');
  static const confidentialityUrl = String.fromEnvironment('CONFIDENTIALITY_URL',
      defaultValue: 'https://www.nchemty.com/p/confidentiality');
  static const accountClosureUrl = String.fromEnvironment('ACCOUNT_CLOSURE_URL',
      defaultValue: 'https://www.nchemty.com/p/account-closure');

  /// Branches and agents (Find an agent). The app reads FIND_US_JSON_URL if
  /// the website offers it (docs/find-us-json.md), else the find-us page.
  static const findUsUrl =
      String.fromEnvironment('FIND_US_URL', defaultValue: 'https://nchemty.com/find-us');
  static const locationsJsonUrl = String.fromEnvironment('FIND_US_JSON_URL',
      defaultValue: 'https://nchemty.com/find-us.json');

  static const idleLockAfter = Duration(minutes: 5);
  static const backgroundLockAfter = Duration(seconds: 60);

  static bool get isProd => flavor == 'prod';
}
