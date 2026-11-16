# The single place to change the project's name and identifiers.
APP_NAME="Lichen"                           # name of the .app
TARGET="Lichen"                             # SwiftPM target (folder in Sources/)
BUNDLE_ID="io.github.namecoder1.lichen"
CASK="lichen"                               # brew install --cask <CASK>
REPO="namecoder1/lichen"                    # the app's GitHub repository
TAP_REPO="namecoder1/homebrew-tap"          # Homebrew tap → brew tap namecoder1/tap
DESCRIPTION="Animated wallpaper that grows a landscape around desktop icons"
MIN_MACOS="13.0"

# Automatic updates (Sparkle). EdDSA public key (`generate_keys -p`): safe to keep in the repo.
# The private key stays in the maintainer's Keychain and in the CI secret SPARKLE_PRIVATE_KEY.
SPARKLE_FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-nXCVWE+lWg4wLzPe+J+sjYIaY1jT1dpVU7Wq1qNCWyc=}"
