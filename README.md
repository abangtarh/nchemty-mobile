# Nchemty Mobile

Flutter app for iOS and Android on Cyclos 4.16.17, using the hybrid model:

- **Cyclos REST directly** for login, balances, history and member transfers.
- **Node middleware / Payment Hub (`/v1`)** for MTN MoMo, loans, ACAO DailySaver
  and KYC. The contract is in [`docs/middleware-contract.md`](docs/middleware-contract.md).

## Get it running

Needs Flutter 3.29 or newer.

```bash
cd nchemty_mobile
# Generate the native iOS/Android shells (only once; keeps lib/ and pubspec)
flutter create --org com.nchemty --project-name nchemty_mobile --platforms ios,android .
# flutter create names it com.nchemty.nchemty_mobile; set the store ID instead:
#   iOS:     ios/Runner.xcodeproj -> PRODUCT_BUNDLE_IDENTIFIER = com.nchemty.ebank
#   Android: android/app/build.gradle(.kts) -> applicationId = "com.nchemty.ebank"
#            (namespace can stay as generated)
flutter pub get
flutter test

flutter run \
  --dart-define=FLAVOR=dev \
  --dart-define=CYCLOS_URL=https://<your-cyclos-test>/api \
  --dart-define=HUB_URL=https://<your-hub-test>/v1 \
  --dart-define=MAIN_ACCOUNT_TYPE=<main account type internal name>
```

### Native settings after `flutter create`

- **iOS `ios/Runner/Info.plist`:** add `NSFaceIDUsageDescription` and
  `NSCameraUsageDescription` (needed by local_auth, image_picker and
  mobile_scanner for QR payments).
- **Android camera:** add `<uses-permission android:name="android.permission.CAMERA"/>`.
- **Android:** `android/app/src/main/kotlin/.../MainActivity.kt` must extend
  `FlutterFragmentActivity` (local_auth needs it); set `minSdk = 26` in
  `android/app/build.gradle(.kts)`; add `<uses-permission android:name="android.permission.USE_BIOMETRIC"/>`.
- **Screenshots:** block them on sensitive screens (`FLAG_SECURE` on Android,
  a privacy overlay on iOS) before beta.

## Structure

```
lib/
  core/      config (Env), network (Dio + auth interceptor), storage,
             theme, l10n (EN/FR), money formatting
  data/      cyclos_api.dart, hub_api.dart, models
  features/  auth, home, history, transfer, momo, loans, kyc,
             qr (native Cyclos tickets / easy-invoice QR)
  router.dart  auth-guarded routes
```

## Auth flow

1. Username + password → `POST /auth/session` → Cyclos `sessionToken`, kept in
   Keychain / Keystore.
2. Member creates a 4-digit PIN; biometrics optional.
3. Next launch: PIN or biometrics → `GET /auth` checks the token is still valid.
   Expired → password again. 5 wrong PINs → full sign-out.
4. Payments send the Cyclos confirmation password in `Confirmation-Password`.
5. Locks after 5 min idle or 60 s in the background.

## Store listing (ships as an update to the existing app)

| Store | Field | Value |
| --- | --- | --- |
| App Store | App name | Nchemty |
| App Store | Apple ID | 6757865496 |
| App Store | SKU | 015012026 |
| App Store | Live version | 1.0 (next release must be higher, e.g. 1.1.0) |
| App Store | Bundle ID | com.nchemty.ebank (confirm in App Store Connect > App Information) |
| Google Play | Package name | com.nchemty.ebank (confirm in Play Console, under the app name) |
| Google Play | Version code | TODO: the `+N` in pubspec `version` must be higher than the live versionCode |

The bundle ID and package name must match exactly, and builds must be
signed by the same Apple team and with the same Android upload key as the
current app, or the stores will treat this as a new app.

## Before release (tracked as TODOs in code)

- Switch the local PIN to Cyclos device PINs once confirmed on the instance.
- Certificate pinning for ebank / brg1 (`core/network/dio_factory.dart`).
- Root / jailbreak detection; push notifications (FCM / APNs); Sentry.
- Check every Cyclos path against your instance's `/api/openapi.yaml`.
- Replace the placeholder green/gold palette with the official brand.
- Move strings to ARB files and `flutter gen-l10n`.
