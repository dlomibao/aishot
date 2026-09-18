#!/bin/bash
# Wraps the SwiftPM executable in a .app so macOS will activate it and give it
# a menu bar. SwiftPM cannot produce a bundle itself.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/AIShot.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/aishot"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/aishot"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AIShot</string>
  <key>CFBundleDisplayName</key><string>AIShot</string>
  <key>CFBundleIdentifier</key><string>com.dlomibao.aishot</string>
  <key>CFBundleExecutable</key><string>aishot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: unsigned bundles get killed by Gatekeeper on first launch.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"

echo "built $APP"
