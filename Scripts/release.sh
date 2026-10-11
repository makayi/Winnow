#!/bin/zsh
# Builds a Developer ID-signed, notarized and stapled DMG of Winnow, ready for GitHub Releases.
#
# One-time setup (see README "Releasing"):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. Notary credentials saved under the profile name "winnow":
#        xcrun notarytool store-credentials winnow --apple-id <you@example.com> --team-id 9Q6VRKYMZM
#
# Usage: Scripts/release.sh            (version comes from MARKETING_VERSION)
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-9Q6VRKYMZM}"
PROFILE="${NOTARY_PROFILE:-winnow}"
IDENTITY="Developer ID Application"

security find-identity -v -p codesigning | grep -q "$IDENTITY" || {
  echo "No '$IDENTITY' certificate found. Create one in Xcode › Settings › Accounts › Manage Certificates." >&2; exit 1; }

DERIVED=build/DerivedData
OUT=build/release
rm -rf "$OUT/stage" && mkdir -p "$OUT/stage"

echo "▸ Building Release"
xcodebuild -project Winnow.xcodeproj -scheme Winnow -configuration Release -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO clean build | grep -E "error|BUILD"

APP="$DERIVED/Build/Products/Release/Winnow.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/Winnow-$VERSION.dmg"
codesign --verify --deep --strict "$APP"
# Notarization rejects the debugging entitlement Xcode adds to development builds.
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow; then
  echo "The app still has com.apple.security.get-task-allow; notarization would fail." >&2; exit 1
fi

echo "▸ Making $DMG"
ditto "$APP" "$OUT/stage/Winnow.app"
ln -s /Applications "$OUT/stage/Applications"
rm -f "$DMG"
hdiutil create -volname "Winnow" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "▸ Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Checking"
spctl -a -t open --context context:primary-signature -vv "$DMG"
shasum -a 256 "$DMG"
echo "Done: $DMG"
