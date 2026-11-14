#!/usr/bin/env bash
# Builds and signs the two Android APKs:
#   dist/ZapDL-<version>-android.apk         GitHub build (in-app updater ON)
#   dist/ZapDL-<version>-android-store.apk   Myket / Bazaar build (updater OFF,
#                                             no "install packages" permission)
# Both are signed with the SAME key, which is what lets Android update one over
# the other. Never lose or change that key.
#
# Usage (from the project root, after `dart tool/setup.dart`):
#   KEYSTORE=$HOME/zapdl-release.jks KEY_ALIAS=zapdl \
#   KEYSTORE_PASSWORD=... KEY_PASSWORD=... tool/build_android.sh
#
# Needs: flutter, the Android SDK (apksigner from build-tools), bash.
set -euo pipefail

: "${KEYSTORE:?set KEYSTORE to the path of your .jks file}"
: "${KEY_ALIAS:?set KEY_ALIAS}"
: "${KEYSTORE_PASSWORD:?set KEYSTORE_PASSWORD}"
: "${KEY_PASSWORD:?set KEY_PASSWORD}"
[ -f "$KEYSTORE" ] || { echo "Keystore not found: $KEYSTORE" >&2; exit 1; }

VERSION=$(grep -E '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*//; s/\+.*//')
MANIFEST=android/app/src/main/AndroidManifest.xml
[ -f "$MANIFEST" ] || { echo "Run 'dart tool/setup.dart' first." >&2; exit 1; }

# Locate apksigner (newest build-tools).
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
APKSIGNER=$(ls -d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -n1 || true)
[ -x "${APKSIGNER:-}" ] || { echo "apksigner not found under $SDK/build-tools. Set ANDROID_HOME." >&2; exit 1; }

mkdir -p dist
RAW=build/app/outputs/flutter-apk/app-release.apk

sign() { # <in> <out>
  "$APKSIGNER" sign \
    --ks "$KEYSTORE" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass env:KEYSTORE_PASSWORD --key-pass env:KEY_PASSWORD \
    --out "$2" "$1"
  "$APKSIGNER" verify --print-certs "$2" | grep -E 'Signer #1 certificate (DN|SHA-256)'
}

echo "== GitHub build (updater on)"
flutter build apk --release
sign "$RAW" "dist/ZapDL-$VERSION-android.apk"

echo "== Store build (updater off)"
cp "$MANIFEST" "$MANIFEST.bak"
trap 'mv -f "$MANIFEST.bak" "$MANIFEST"' EXIT
sed -i '/REQUEST_INSTALL_PACKAGES/d' "$MANIFEST"
flutter build apk --release --dart-define=STORE_BUILD=true
sign "$RAW" "dist/ZapDL-$VERSION-android-store.apk"

echo
ls -la dist/ZapDL-$VERSION-android*.apk
echo "Check both SHA-256 certificate lines above are IDENTICAL."
