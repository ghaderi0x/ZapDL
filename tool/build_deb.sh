#!/usr/bin/env bash
# Builds a .deb installer (Debian, Ubuntu, Mint...) from the Linux release
# bundle. Run after `flutter build linux --release`.
# Usage: tool/build_deb.sh <version>      Output: dist/ZapDL-<version>-linux-amd64.deb
set -euo pipefail
VERSION="${1:?usage: tool/build_deb.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
[ -d "$BUNDLE" ] || { echo "Build first: flutter build linux --release"; exit 1; }

BIN=$(grep -E '^set\(BINARY_NAME' "$ROOT/linux/CMakeLists.txt" | sed -E 's/.*"([^"]+)".*/\1/')
[ -x "$BUNDLE/$BIN" ] || { echo "Executable '$BIN' not found in $BUNDLE"; exit 1; }

PKG="$ROOT/build/deb/zapdl_${VERSION}"
rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/zapdl" "$PKG/usr/bin" \
         "$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/256x256/apps"

cp -r "$BUNDLE/." "$PKG/opt/zapdl/"
ln -s "/opt/zapdl/$BIN" "$PKG/usr/bin/zapdl"
cp "$ROOT/assets/icon/zapdl.png" "$PKG/usr/share/icons/hicolor/256x256/apps/zapdl.png"

cat > "$PKG/usr/share/applications/zapdl.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=ZapDL
Comment=Fast, honest download manager
Exec=/opt/zapdl/$BIN %U
Icon=zapdl
Categories=Network;FileTransfer;
Terminal=false
StartupWMClass=$BIN
DESKTOP

# Debian versions may not contain "-"; use "~" so 1.0.0-beta.1 sorts before 1.0.0.
DEBV="${VERSION//-/~}"
SIZE=$(du -sk "$PKG/opt" | cut -f1)
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: zapdl
Version: $DEBV
Section: net
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Maintainer: ZapDL <noreply@users.noreply.github.com>
Depends: libgtk-3-0, libayatana-appindicator3-1, libsecret-1-0, libnotify4
Description: Fast, honest download manager
 ZapDL downloads files with multiple connections and resume, and saves videos
 and audio from popular sites.
CONTROL

mkdir -p "$ROOT/dist"
dpkg-deb --root-owner-group --build "$PKG" "$ROOT/dist/ZapDL-${VERSION}-linux-amd64.deb"
echo "Built dist/ZapDL-${VERSION}-linux-amd64.deb"
