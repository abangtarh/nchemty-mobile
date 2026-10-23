# Nchemty Mobile: context for Claude

Flutter app (iOS + Android) for Nchemty Credit Union members, on Cyclos 4.16.17.
Developer: Abang (Sure Engineering & Technologies). Develops on Windows 11
(PowerShell, VS Code); no Mac, so iOS is built in the cloud (Codemagic → TestFlight).

## Architecture (decided: hybrid)
- **Cyclos REST directly** (`lib/data/cyclos/`): login (`POST /auth/session`,
  `Session-Token` header, `Channel: mobile`), accounts, history, member payments
  (preview → `POST /self/payments` with `Confirmation-Password` header), and
  **native Cyclos QR** via the Tickets API (`cyclos_qr_api.dart`).
- **Node middleware / Payment Hub `/v1`** (`lib/data/middleware/hub_api.dart`):
  MTN MoMo top-up/cash-out, loans (LoanCoreLib), ACAO DailySaver (ACAOCoreLib),
  KYC. Contract in `docs/middleware-contract.md`. These routes are NOT built yet,
  so those screens error at runtime until the hub exists.
- Cyclos is the single source of truth for balances; the app never computes them.
- Stack: Riverpod 2.x, go_router 14, dio 5, flutter_secure_storage, local_auth,
  image_picker, mobile_scanner. EN/FR strings in `lib/core/l10n/strings.dart`.

## Confirmed facts
- QR codes from the instance look like `https://ebank.nchemty.com/pay/{32-char code}`.
  The app resolves the code by trying `GET /tickets/{code}` first, else treats it
  as an easy invoice. Only the Cyclos host is accepted. Payee name always comes
  from Cyclos, never from the QR.
- Store listing: existing app "Nchemty", Apple ID 6757865496, SKU 015012026, live
  version 1.0, published under Sure Engineering. App ID: `com.nchemty.ebank` on
  both stores (verify against App Store Connect / Play Console before release).
- pubspec version 1.1.0+2; Android versionCode must exceed the live one (unknown).
- MoMo cash-out fee rules live in the hub: 35 XAF flat under 5 000 XAF; from
  5 000 XAF, ceiling(0.7% + 4), min 39 XAF.

## Local setup status (Windows)
Done: Flutter 3.47.7 / Dart 3.13 installed, Android toolchain OK, repo cloned,
`flutter create` run, analyzer clean apart from items fixed in PR #1.
Still to do, in order:
1. Delete `test/widget_test.dart` (flutter create's demo test).
2. Set app ID: `PRODUCT_BUNDLE_IDENTIFIER` → `com.nchemty.ebank` in
   `ios/Runner.xcodeproj/project.pbxproj` (also the `.RunnerTests` variant);
   `applicationId = "com.nchemty.ebank"` and `minSdk = 26` in
   `android/app/build.gradle.kts` (leave `namespace` as generated).
3. `MainActivity.kt` must extend `FlutterFragmentActivity` (local_auth needs it).
4. AndroidManifest: `CAMERA` and `USE_BIOMETRIC` permissions.
5. iOS `Info.plist`: `NSCameraUsageDescription`, `NSFaceIDUsageDescription`.
6. `flutter analyze` + `flutter test` clean, then `flutter run` on an Android
   phone with `--dart-define=CYCLOS_URL=... --dart-define=HUB_URL=...`.
7. Commit `android/` and `ios/` on a branch and open a PR.
8. Add `codemagic.yaml` for iOS → TestFlight and Android → Play internal track.

## Working rules
- Never commit to `main`; branch + PR. Never commit keystores, `key.properties`,
  `.p8`/`.p12`, or `.env` (see `.gitignore`).
- Transfers move real money: test with a test member or a Cyclos test network.
- Check Cyclos paths against the instance's `/api/openapi.yaml` when unsure.
