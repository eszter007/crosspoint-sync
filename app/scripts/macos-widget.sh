#!/bin/sh
# Builds the WidgetKit extension (src-tauri/gen/apple/CrossPointWidget) for macOS,
# embeds it in the Tauri .app, and signs both with one App Group so the widget can
# read what the app writes. Run after `npm run tauri build -- --bundles app`.
#
#   MAC_SIGN_IDENTITY  codesigning identity (default: the first Apple Development one)
#   APP                the .app to update (default: the release bundle)
set -eu
cd "$(dirname "$0")/.."

APP=${APP:-src-tauri/target/release/bundle/macos/CrossPoint Sync.app}
IDENTITY=${MAC_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -n 1)}
[ -n "$IDENTITY" ] || { echo "No codesigning identity found; set MAC_SIGN_IDENTITY." >&2; exit 1; }
# The team ID is the certificate's organizational unit.
TEAM=$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject -nameopt multiline | sed -n 's/.*organizationalUnitName *= *//p' | head -n 1)
[ -n "$TEAM" ] || { echo "Could not read the team ID from $IDENTITY." >&2; exit 1; }
# Without a provisioning profile, macOS App Groups must start with the team ID.
GROUP="$TEAM.com.crosspointreader.sync"
SRC=src-tauri/gen/apple/CrossPointWidget
WORK=src-tauri/target/macos-widget
APPEX="$APP/Contents/PlugIns/CrossPointWidget.appex"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")

rm -rf "$WORK" "$APPEX"
mkdir -p "$WORK" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

for arch in arm64 x86_64; do
  xcrun --sdk macosx swiftc -target "$arch-apple-macos14.0" -O -parse-as-library -application-extension \
    -module-name CrossPointWidget -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$WORK/CrossPointWidget-$arch" "$SRC"/*.swift
done
lipo -create -output "$APPEX/Contents/MacOS/CrossPointWidget" "$WORK"/CrossPointWidget-*
cp "$SRC/PreviewCover.jpg" "$APPEX/Contents/Resources/"

PLIST="$APPEX/Contents/Info.plist"
cp "$SRC/Info.plist" "$PLIST"
set_key() { /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" 2>/dev/null || true; /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"; }
set_key CFBundleDevelopmentRegion string en
set_key CFBundleExecutable string CrossPointWidget
set_key CFBundleIdentifier string com.crosspointreader.sync.widget
set_key CFBundleName string CrossPointWidget
set_key CFBundleShortVersionString string "$VERSION"
set_key CFBundleVersion string "$BUILD"
set_key LSMinimumSystemVersion string 14.0
/usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" "$PLIST"
set_key CrossPointAppGroup string "$GROUP"

/usr/libexec/PlistBuddy -c 'Delete :CrossPointAppGroup' "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CrossPointAppGroup string $GROUP" "$APP/Contents/Info.plist"

# macOS only loads sandboxed widgets; the app itself stays unsandboxed.
cat > "$WORK/widget.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
EOF
cat > "$WORK/app.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
EOF

codesign --force --options runtime --sign "$IDENTITY" --entitlements "$WORK/widget.entitlements" "$APPEX"
codesign --force --options runtime --sign "$IDENTITY" --entitlements "$WORK/app.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "Widget embedded and signed ($IDENTITY, group $GROUP)."
