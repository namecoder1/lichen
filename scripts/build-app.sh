#!/usr/bin/env bash
# Builds dist/<APP_NAME>.app (universal arm64 + x86_64) and dist/<APP_NAME>-<version>.zip.
#
#   scripts/build-app.sh 0.1.0
#
# Signing:
#   - no variables → ad-hoc signature (fine locally; Gatekeeper blocks it once downloaded)
#   - SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" → signed with the hardened runtime
# Notarization (requires SIGN_IDENTITY):
#   - NOTARY_PROFILE=<profile created with `xcrun notarytool store-credentials`>, or
#   - APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (app-specific password)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

VERSION="${1:-0.0.0-dev}"

# Without SIGN_IDENTITY, use the first "Developer ID Application" certificate in the keychain, if any.
# With a stable signature macOS remembers the Accessibility permission across rebuilds
# (with an ad-hoc signature the permission only applies to that exact binary).
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

echo "▸ Universal build $VERSION"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$TARGET"

echo "▸ Bundle $APP"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp -R Resources/themes Resources/thumbs Resources/*.lproj "$APP/Contents/Resources/"
cp LICENSE NOTICE "$APP/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi

echo "▸ Screen saver Lichen.saver"
SAVER="$APP/Contents/Resources/Lichen.saver"
SAVER_TMP="$(mktemp -d)"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -module-name LichenSaver -target "$arch-apple-macos$MIN_MACOS" \
    -emit-library -Xlinker -bundle -o "$SAVER_TMP/LichenSaver-$arch" \
    Sources/Lichen/Shared/*.swift Saver/LichenSaverView.swift \
    -framework ScreenSaver -framework WebKit -framework IOKit
done
lipo -create "$SAVER_TMP"/LichenSaver-* -output "$SAVER/Contents/MacOS/LichenSaver"
cp -R Resources/themes Resources/thumbs Resources/*.lproj "$SAVER/Contents/Resources/"
cat > "$SAVER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>  <string>en</string>
  <key>CFBundleLocalizations</key>      <array><string>en</string><string>it</string></array>
  <key>CFBundleName</key>               <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>         <string>LichenSaver</string>
  <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID.saver</string>
  <key>CFBundlePackageType</key>        <string>BNDL</string>
  <key>CFBundleShortVersionString</key> <string>$VERSION</string>
  <key>CFBundleVersion</key>            <string>$VERSION</string>
  <key>NSPrincipalClass</key>           <string>LichenSaverView</string>
  <key>LSMinimumSystemVersion</key>     <string>$MIN_MACOS</string>
</dict>
</plist>
PLIST
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SAVER"
else
  codesign --force --sign - "$SAVER"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>  <string>en</string>
  <key>CFBundleLocalizations</key>      <array><string>en</string><string>it</string></array>
  <key>CFBundleName</key>               <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>$VERSION</string>
  <key>CFBundleVersion</key>            <string>$VERSION</string>
  <key>CFBundleIconFile</key>           <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>     <string>$MIN_MACOS</string>
  <key>LSUIElement</key>                <true/>
  <key>NSHumanReadableCopyright</key>   <string>GPL-3.0-or-later</string>
$(if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then cat <<SPARKLE
  <key>SUFeedURL</key>                  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>              <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>    <true/>
  <key>SUScheduledCheckInterval</key>   <integer>86400</integer>
SPARKLE
fi)
</dict>
</plist>
PLIST
[[ -z "$SPARKLE_PUBLIC_KEY" ]] && echo "  (no SPARKLE_PUBLIC_KEY: automatic updates disabled)"

# Sparkle: sign the nested parts first, from the inside out.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Developer ID signature"
  SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
else
  echo "▸ Ad-hoc signature (no SIGN_IDENTITY)"
  SIGN=(codesign --force --sign -)
fi
"${SIGN[@]}" "$SPK/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPK/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPK/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPK/Versions/B/Updater.app"
"${SIGN[@]}" "$SPK"
"${SIGN[@]}" "$APP"
codesign --verify --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${SIGN_IDENTITY:-}" ]] && [[ -n "${NOTARY_PROFILE:-}${APPLE_ID:-}" ]]; then
  echo "▸ Notarization"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" --wait
  fi
  xcrun stapler staple "$APP"
  rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "▸ Done: $ZIP"
shasum -a 256 "$ZIP"
