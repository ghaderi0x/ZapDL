# Release preparation guide

**Nothing in this guide has been executed.** It lists what a maintainer must do; no build, signing, store submission or approval has happened. Store requirements change; re-check each store's current documentation.

Run first: `dart tool/setup.dart`, `flutter analyze`, `flutter test`, and manual testing on every target platform.

## Android (GitHub, Cafe Bazaar, Myket, Google Play)

1. **Application ID:** `com.uniqueone.zapdl` (set by `tool/setup.dart`). It can never change after the first public release.
2. **Two APKs, one key.** `tool/build_android.sh` builds and signs both with the same permanent keystore:
   - `ZapDL-X.Y.Z-android.apk`: GitHub build, in-app updater on, `REQUEST_INSTALL_PACKAGES` present.
   - `ZapDL-X.Y.Z-android-store.apk`: built with `--dart-define=STORE_BUILD=true`; updater hidden, `REQUEST_INSTALL_PACKAGES` removed. Upload this one to Myket / Bazaar.
3. **Signing:** create the keystore once (see `docs/GITHUB_GUIDE.md`), back it up offline, never commit it. Android refuses to update an app signed with a different key, so every source must use this key.
4. **Store assets:** screenshots, descriptions in the supported languages, privacy policy (ZapDL collects no personal data).
5. **Unverified:** Myket's and Bazaar's current rules (whether they re-sign uploads, policy on self-updating apps and install permissions, AAB vs APK) were NOT checked. Read their developer docs before submitting. Google Play needs an AAB (`flutter build appbundle`) and Play App Signing, which is a different signing model and is not scripted here.

## Windows
1. `flutter build windows --release` on Windows with Visual Studio's "Desktop development with C++" workload.
2. Package the `build/windows/x64/runner/Release` folder as an installer (MSIX via the `msix` package, or Inno Setup/NSIS). Code-sign the installer to avoid SmartScreen warnings.
3. Document the install and uninstall steps in the release notes.

## Linux
1. Install build dependencies: `clang cmake ninja-build pkg-config libgtk-3-dev`.
2. `flutter build linux --release`.
3. Package `build/linux/x64/release/bundle` as a tarball, AppImage, `.deb`, or Flatpak, and provide a `.desktop` file and icon. Test on at least one GNOME and one KDE distribution.

## macOS
1. `flutter build macos --release` on a Mac with Xcode.
2. Entitlements for network and file access are added by `setup.dart`; review them before release.
3. Sign with a Developer ID Application certificate, notarize with `xcrun notarytool`, then staple the ticket. A paid Apple Developer account is required.
4. Distribute as a notarized `.dmg`, or via the Mac App Store (which requires sandbox compliance and review).

## iOS
1. Requires a Mac, Xcode and an Apple Developer Program membership.
2. Set the bundle identifier, team and signing in Xcode; configure icons and launch screen.
3. `flutter build ipa --release`, then upload through Xcode or Transmitter to TestFlight and App Store Connect.
4. Note: ZapDL does not yet implement iOS background transfers; downloads pause when the app is suspended. Describe this accurately in the listing.

## Before tagging a release
- [ ] All tests pass and `flutter analyze` is clean
- [ ] Manual regression on each target platform
- [ ] Native-speaker review of all translations
- [ ] Update `CHANGELOG.md`, `pubspec.yaml` version and `lib/core/app_info.dart`
- [ ] README and `docs/CHECKLIST.md` match reality


## GitHub releases and the in-app updater

The updater reads `https://github.com/ghaderi0x/ZapDL/releases`. Push a tag `vX.Y.Z` (matching `pubspec.yaml` and `lib/core/app_info.dart`) and `.github/workflows/release.yml` builds and publishes: `ZapDL-X.Y.Z-android.apk`, `-windows-x64-setup.exe`, `-windows-x64.zip`, `-linux-x64.tar.gz`, `-macos.dmg` and `SHA256SUMS.txt`. Tags with `-` (e.g. `v1.2.0-beta.1`) become pre-releases, offered only to users who enable the beta channel. Release notes come from the matching `CHANGELOG.md` section. **The workflow has never run;** test it with a throwaway tag.

**Android signing:** see the Android section above and `docs/GITHUB_GUIDE.md` (secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`). To bump versions use `dart tool/bump_version.dart X.Y.Z`.
