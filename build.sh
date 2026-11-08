#!/bin/zsh
# Construit AirPodsMouse.app (bundle nécessaire pour l'autorisation « Mouvements »)
set -e
cd "$(dirname "$0")"
APP=AirPodsMouse.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -O main.swift Viewer3D.swift -o $APP/Contents/MacOS/AirPodsMouse -framework CoreMotion -framework AppKit -framework SceneKit -framework Metal
cat > $APP/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.airpodsmouse</string>
  <key>CFBundleName</key><string>AirPodsMouse</string>
  <key>CFBundleExecutable</key><string>AirPodsMouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMotionUsageDescription</key><string>Utilise les capteurs de mouvement des AirPods pour déplacer le curseur.</string>
</dict></plist>
EOF
codesign --force --sign - $APP
echo "OK → open $APP"
