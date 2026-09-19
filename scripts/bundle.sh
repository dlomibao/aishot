#!/bin/bash
# Wraps the SwiftPM executable in a .app so macOS will activate it and give it
# a menu bar. SwiftPM cannot produce a bundle itself.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/AIShot.app"
# Releases stamp the tag in; local builds are 0.0.0-dev so a stray build is
# never mistaken for a release.
VERSION="${VERSION:-0.0.0-dev}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/aishot"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/aishot"

# Icon is generated from vectors at every iconset rung, not downscaled from one
# master, so the 16px rung stays legible.
swift scripts/make-icon.swift build/AIShot.iconset
iconutil -c icns build/AIShot.iconset -o "$APP/Contents/Resources/AIShot.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AIShot</string>
  <key>CFBundleDisplayName</key><string>AIShot</string>
  <key>CFBundleIdentifier</key><string>com.dlomibao.aishot</string>
  <key>CFBundleExecutable</key><string>aishot</string>
  <key>CFBundleIconFile</key><string>AIShot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>__VERSION__</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

sed -i '' "s/__VERSION__/$VERSION/g" "$APP/Contents/Info.plist"

# PkgInfo is legacy but every app bundle on disk has one, and Spotlight's
# importer is happier typing the bundle when it is present.
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: unsigned bundles get killed by Gatekeeper on first launch.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"

echo "built $APP (version $VERSION)"
