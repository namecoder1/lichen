# Unico punto da cambiare per nome e identificativi del progetto.
APP_NAME="Lichen"                           # nome della .app
TARGET="Lichen"                             # target SwiftPM (cartella in Sources/)
BUNDLE_ID="io.github.namecoder1.lichen"
CASK="lichen"                               # brew install --cask <CASK>
REPO="namecoder1/lichen"                    # repository GitHub dell'app
TAP_REPO="namecoder1/homebrew-tap"          # tap Homebrew → brew tap namecoder1/tap
DESCRIPTION="Sfondo animato che fa crescere un paesaggio attorno alle icone del desktop"
MIN_MACOS="13.0"

# Aggiornamenti automatici (Sparkle). Chiave pubblica EdDSA (`generate_keys -p`): può stare nel repo.
# La privata resta nel Portachiavi del maintainer e nel secret SPARKLE_PRIVATE_KEY della CI.
SPARKLE_FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-nXCVWE+lWg4wLzPe+J+sjYIaY1jT1dpVU7Wq1qNCWyc=}"
