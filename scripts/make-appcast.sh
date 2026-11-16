#!/usr/bin/env bash
# Signs the release zip with Sparkle's EdDSA key and writes dist/appcast.xml.
#
#   SPARKLE_PRIVATE_KEY="<key exported with generate_keys -x>" scripts/make-appcast.sh 0.4.0
#
# The appcast is published as an asset of every release; the app reads it from
# https://github.com/<REPO>/releases/latest/download/appcast.xml
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

VERSION="$1"
ZIP="dist/$APP_NAME-$VERSION.zip"
SIGN_UPDATE="$(find .build/artifacts -path '*Sparkle/bin/sign_update' -type f | head -1)"
[[ -x "$SIGN_UPDATE" ]] || { echo "sign_update not found: run swift package resolve first"; exit 1; }

# prints: sparkle:edSignature="..." length="..."
ATTRS="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")"
URL="https://github.com/$REPO/releases/download/v$VERSION/$APP_NAME-$VERSION.zip"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>$APP_NAME $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $ATTRS/>
    </item>
  </channel>
</rss>
XML
echo "▸ dist/appcast.xml"
