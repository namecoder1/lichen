#!/usr/bin/env bash
# Crea dist/<APP_NAME>.app (universale arm64 + x86_64) e dist/<APP_NAME>-<versione>.zip.
#
#   scripts/build-app.sh 0.1.0
#
# Firma:
#   - senza variabili  → firma ad-hoc (va bene in locale, Gatekeeper la blocca se scaricata)
#   - SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" → firma con hardened runtime
# Notarizzazione (richiede SIGN_IDENTITY):
#   - NOTARY_PROFILE=<profilo creato con `xcrun notarytool store-credentials`>, oppure
#   - APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (password specifica per l'app)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

VERSION="${1:-0.0.0-dev}"

# Senza SIGN_IDENTITY usa il primo certificato "Developer ID Application" del portachiavi, se c'è.
# Con una firma stabile macOS ricorda il permesso Accessibilità anche dopo una ricompilazione
# (con la firma ad-hoc il permesso vale solo per quell'esatto eseguibile).
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

echo "▸ Compilazione universale $VERSION"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$TARGET"

echo "▸ Bundle $APP"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp -R Resources/themes Resources/thumbs "$APP/Contents/Resources/"
cp LICENSE NOTICE "$APP/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi

echo "▸ Salvaschermo Lichen.saver"
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
cp -R Resources/themes Resources/thumbs "$SAVER/Contents/Resources/"
cat > "$SAVER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
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
[[ -z "$SPARKLE_PUBLIC_KEY" ]] && echo "  (nessuna SPARKLE_PUBLIC_KEY: aggiornamenti automatici disattivati)"

# Sparkle: si firmano prima i pezzi annidati, dall'interno verso l'esterno.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Firma Developer ID"
  SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
else
  echo "▸ Firma ad-hoc (nessun SIGN_IDENTITY)"
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
  echo "▸ Notarizzazione"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" --wait
  fi
  xcrun stapler staple "$APP"
  rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "▸ Fatto: $ZIP"
shasum -a 256 "$ZIP"
