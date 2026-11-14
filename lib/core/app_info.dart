/// Keep in sync with `version:` in pubspec.yaml (enforced by
/// test/core/app_info_test.dart).
const appVersion = '1.0.0';
const appLicense = 'MIT';

/// True for the APK uploaded to app stores (Myket, Bazaar). Those stores
/// update the app themselves, so the in-app updater is switched off:
/// `flutter build apk --dart-define=STORE_BUILD=true`.
const isStoreBuild = bool.fromEnvironment('STORE_BUILD');
