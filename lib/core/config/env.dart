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

  /// Middleware contract base: the Unified Banking Platform's app gateway,
  /// ending in /api/v1/app (no trailing slash). Set the real host per
  /// environment with --dart-define=HUB_URL=...
  static const hubBaseUrl = String.fromEnvironment(
    'HUB_URL',
    defaultValue: 'https://api.nchemty.com/api/v1/app',
  );

  /// Cyclos channel internal name used for mobile sessions.
  static const cyclosChannel =
      String.fromEnvironment('CYCLOS_CHANNEL', defaultValue: 'mobile');

  /// Internal name of the member's main account type in Cyclos.
  static const mainAccountType =
      String.fromEnvironment('MAIN_ACCOUNT_TYPE', defaultValue: 'member');

  /// MoMo, loans and savings through the platform's app gateway. Off by
  /// default so a build without HUB_URL shows "coming soon" instead of
  /// failing. Turn on with --dart-define=HUB_ENABLED=true.
  static const hubEnabled =
      bool.fromEnvironment('HUB_ENABLED', defaultValue: false);

  /// Identity re-verification in the app (selfie + ID). The platform does not
  /// serve these routes yet; members verify through onboarding or a branch.
  static const kycEnabled =
      bool.fromEnvironment('KYC_ENABLED', defaultValue: false);

  static const idleLockAfter = Duration(minutes: 5);
  static const backgroundLockAfter = Duration(seconds: 60);

  static bool get isProd => flavor == 'prod';
}
