#!/bin/sh
# Builds a universal (Apple Silicon + Intel) Mac app with the widgets, packs it into
# a .dmg, and notarizes it, ready to attach to a GitHub release.
#
#   MAC_SIGN_IDENTITY  "Developer ID Application: …" (required; Apple Development
#                      builds only run on your own Mac)
#   NOTARY_PROFILE     notarytool keychain profile, made once with
#                      `xcrun notarytool store-credentials`. Unset: skip notarizing.
#
# Needs rustup with both Mac targets (Homebrew's rust only builds for this Mac):
#   rustup target add aarch64-apple-darwin x86_64-apple-darwin
set -eu
cd "$(dirname "$0")/.."

case "${MAC_SIGN_IDENTITY:-}" in
  "Developer ID Application: "*) ;;
  *) echo "Set MAC_SIGN_IDENTITY to a Developer ID Application identity." >&2; exit 1 ;;
esac

TARGET=universal-apple-darwin
npm run tauri build -- --target "$TARGET" --bundles app
APP="src-tauri/target/$TARGET/release/bundle/macos/CrossPoint Sync.app"
APP="$APP" sh scripts/macos-widget.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="src-tauri/target/$TARGET/release/bundle"
DMG="$OUT/CrossPoint-Sync-$VERSION.dmg"
# The .dmg is made here, not by Tauri, because the widget script changes the .app.
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "CrossPoint Sync" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$MAC_SIGN_IDENTITY" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
else
  echo "NOTARY_PROFILE not set: $DMG is signed but not notarized." >&2
fi
echo "$DMG"
