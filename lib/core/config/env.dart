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

  static const idleLockAfter = Duration(minutes: 5);
  static const backgroundLockAfter = Duration(seconds: 60);

  static bool get isProd => flavor == 'prod';
}
