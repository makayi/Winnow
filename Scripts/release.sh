#!/bin/zsh
# Builds a Developer ID-signed, notarized and stapled DMG of Winnow, ready for GitHub Releases.
#
# One-time setup (see README "Releasing"):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. Notary credentials saved under the profile name "winnow":
#        xcrun notarytool store-credentials winnow --apple-id <you@example.com> --team-id 9Q6VRKYMZM
#
#   3. The Sparkle signing key in your keychain (account "winnow"), made once with Sparkle's generate_keys.
#
# Usage: Scripts/release.sh   (version from MARKETING_VERSION; bump CURRENT_PROJECT_VERSION every release,
#                              since Sparkle compares build numbers)
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
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

echo "▸ Signing Sparkle's helpers for notarization"
FW="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(codesign -f -s "$IDENTITY" -o runtime --timestamp)
"${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW"
"${SIGN[@]}" "$APP"
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

echo "▸ Writing appcast.xml"
SPARKLE_BIN=$(dirname "$(find "$DERIVED/SourcePackages/artifacts" -name sign_update -type f | head -1)")
SIG_ATTRS=$("$SPARKLE_BIN/sign_update" --account winnow "$DMG")   # sparkle:edSignature="…" length="…"
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Winnow</title>
    <link>https://github.com/makayi/Winnow</link>
    <item>
      <title>Winnow $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/makayi/Winnow/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/makayi/Winnow/releases/download/v$VERSION/Winnow-$VERSION.dmg" type="application/octet-stream" $SIG_ATTRS/>
    </item>
  </channel>
</rss>
XML
echo "Done: $DMG"
echo "Next: publish the GitHub release v$VERSION with $DMG, then commit and push appcast.xml."
