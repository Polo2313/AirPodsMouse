#!/bin/zsh
# Construit AirPodsMouse.app (signée), et l'installe dans /Applications.
#   scripts/build-app.sh            → compile, assemble, signe, installe
#   NO_INSTALL=1 scripts/build-app.sh  → sans installer
set -euo pipefail
cd "$(dirname "$0")/.."
APP=AirPodsMouse.app
VERSION=2.0

# Appli universelle : Apple Silicon + Intel (deux compilations réunies par lipo)
BINS=()
for ARCH in arm64 x86_64; do
  swift build -c release --product AirPodsMouse --arch $ARCH
  BINS+=("$(swift build -c release --product AirPodsMouse --arch $ARCH --show-bin-path)/AirPodsMouse")
done

[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift
scripts/check-strings.sh

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
lipo -create "${BINS[@]}" -output $APP/Contents/MacOS/AirPodsMouse
cp Resources/AppIcon.icns $APP/Contents/Resources/
cp -R Resources/*.lproj $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.airpodsmouse</string>
  <key>CFBundleName</key><string>AirPodsMouse</string>
  <key>CFBundleDisplayName</key><string>AirPodsMouse</string>
  <key>CFBundleExecutable</key><string>AirPodsMouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>fr</string>
  <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>AirPodsMouse</string>
  <key>NSMotionUsageDescription</key><string>AirPodsMouse lit les mouvements de tes AirPods pour déplacer le curseur avec ta tête.</string>
</dict></plist>
EOF

# Signature : identité stable → l'autorisation Accessibilité reste valable d'une version à l'autre.
SIGN_ID=${SIGN_ID:-$(security find-identity -p codesigning 2>/dev/null | grep -m1 -E '"(AirPodsMouse|Apple Development|Developer ID)' | sed -E 's/.*"([^"]*)".*/\1/')}
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --sign "$SIGN_ID" $APP
  echo "Signé avec : $SIGN_ID"
else
  codesign --force --sign - $APP
  echo "⚠️  Signature ad-hoc : l'autorisation Accessibilité sera à refaire après chaque version."
fi

if [[ -z "${NO_INSTALL:-}" ]]; then
  pkill -f "$APP/Contents/MacOS/AirPodsMouse" 2>/dev/null || true
  rm -rf /Applications/$APP
  cp -R $APP /Applications/
  echo "OK → installée dans /Applications"
fi
