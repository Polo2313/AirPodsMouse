#!/bin/zsh
# Crée AirPodsMouse-<version>.dmg : fond illustré, appli à gauche, raccourci Applications à droite,
# et une aide « Si macOS bloque l'ouverture ». À lancer après scripts/build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=AirPodsMouse.app
[[ -d $APP ]] || { echo "Construis d'abord l'appli : scripts/build-app.sh"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $APP/Contents/Info.plist)
NAME="AirPodsMouse"
DMG="dist/AirPodsMouse-$VERSION.dmg"
WORK=$(mktemp -d)
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background" dist

cp -R $APP "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift scripts/dmg-background.swift "$STAGE/.background/fond.png" >/dev/null
cp "docs/Si macOS bloque l'ouverture.txt" "$STAGE/"

# Image disque modifiable, mise en page dans le Finder, puis compression
RW="$WORK/rw.dmg"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
MNT="/Volumes/$NAME"
sleep 1
if osascript <<EOF
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 100
    set text size of opts to 13
    set background picture of opts to file ".background:fond.png"
    set position of item "$APP" of container window to {170, 175}
    set position of item "Applications" of container window to {470, 175}
    set position of item "Si macOS bloque l'ouverture.txt" of container window to {320, 305}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then echo "Mise en page appliquée"
else echo "⚠️  Mise en page du Finder impossible (autorisation refusée ?) : .dmg sans fond"
fi
cp Resources/AppIcon.icns "$MNT/.VolumeIcon.icns" && SetFile -a C "$MNT" 2>/dev/null || true
sync
hdiutil detach -quiet "$DEV"
rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$WORK"
echo "OK → $DMG ($(du -h "$DMG" | cut -f1))"
