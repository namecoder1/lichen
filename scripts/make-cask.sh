#!/usr/bin/env bash
# Stampa il cask Homebrew per una versione già pubblicata nelle GitHub Releases.
#   scripts/make-cask.sh 0.1.0 <sha256-dello-zip> > Casks/<cask>.rb
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

VERSION="$1"
SHA="$2"

cat <<RUBY
cask "$CASK" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/$APP_NAME-#{version}.zip"
  name "$APP_NAME"
  desc "$DESCRIPTION"
  homepage "https://github.com/$REPO"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "$APP_NAME.app"

  zap trash: "~/Library/Preferences/$BUNDLE_ID.plist"
end
RUBY
