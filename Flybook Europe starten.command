#!/bin/zsh
set -e
cd "$(dirname "$0")"

/usr/bin/xcrun swift build

BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_DIR="$HOME/Applications/Flybook Europe.app"

# Eine bereits laufende Instanz enthaelt weiterhin den alten Code im Speicher.
# Erst nach erfolgreichem Build beenden, dann das Bundle austauschen.
/usr/bin/osascript \
  -e 'tell application id "de.flybook.europe" to quit' \
  >/dev/null 2>&1 || true
for attempt in {1..30}; do
  /usr/bin/pgrep -x "Flybook Europe" >/dev/null 2>&1 || break
  /bin/sleep 0.1
done

/bin/mkdir -p "$HOME/Applications"
/bin/mkdir -p "$APP_DIR/Contents/MacOS"
/bin/mkdir -p "$APP_DIR/Contents/Resources"
/bin/cp "Sources/FlybookEurope/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$BUILD_DIR/Flybook Europe" "$APP_DIR/Contents/MacOS/Flybook Europe"
/bin/cp "Sources/FlybookEurope/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
/bin/rm -rf "$APP_DIR/Contents/Resources/FlybookEurope_FlybookEurope.bundle"
/usr/bin/ditto \
  "$BUILD_DIR/FlybookEurope_FlybookEurope.bundle" \
  "$APP_DIR/Contents/Resources/FlybookEurope_FlybookEurope.bundle"
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/find "$APP_DIR" -name '._*' -delete
/usr/bin/find "$APP_DIR" -exec /usr/bin/xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
/usr/bin/find "$APP_DIR" -exec /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null
/usr/bin/open -n "$APP_DIR"
