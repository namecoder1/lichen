# Maintaining Lichen

The operational handbook: how to ship a release, which credentials exist and when they expire,
how to update the Deskland themes. No secrets live here, only procedures.

## Release checklist

1. **Changelog.** Add a section to `CHANGELOG.md`:
   ```markdown
   ## [0.6.0] — 2026-12-01
   ### Added / Changed / Fixed
   - ...
   ```
   The release workflow copies this section verbatim into the GitHub Release notes (and Sparkle
   shows them). The heading must be exactly `## [X.Y.Z]`.
2. **Test locally:** `scripts/build-app.sh 0.6.0` → `dist/Lichen.app`. Check at least one animated
   theme, one static theme, the panel, ripples and the lock-screen option. For Swift changes that
   touch windows, symbols or wallpapers, also test on macOS 13 (Intel).
3. **Optional pre-release** (exercises signing and notarization without touching users):
   ```sh
   git tag v0.6.0-rc.1 && git push origin v0.6.0-rc.1
   ```
   Tags with a hyphen become GitHub pre-releases: no tap update, and Sparkle ignores them because
   the feed is `releases/latest/download/appcast.xml`. Delete them afterwards:
   ```sh
   gh release delete v0.6.0-rc.1 --cleanup-tag -y && git fetch --prune --prune-tags
   ```
4. **Release:**
   ```sh
   git commit -am "Release 0.6.0" && git push
   git tag v0.6.0 && git push origin v0.6.0
   gh run watch          # about 3 minutes
   ```
5. **Verify** (all must pass):
   ```sh
   gh release view v0.6.0                                       # Latest, zip + appcast.xml
   curl -sL https://github.com/namecoder1/lichen/releases/latest/download/appcast.xml | grep shortVersionString
   gh api repos/namecoder1/homebrew-tap/contents/Casks/lichen.rb -q .content | base64 -d | head -3
   cd "$(mktemp -d)" && curl -sLO https://github.com/namecoder1/lichen/releases/download/v0.6.0/Lichen-0.6.0.zip \
     && ditto -x -k Lichen-0.6.0.zip . && spctl -a -vv Lichen.app && lipo -archs Lichen.app/Contents/MacOS/Lichen
   ```
   `spctl` must say `source=Notarized Developer ID`; `lipo` must list `x86_64 arm64`.
   Finally, on a Mac running the previous version: menu ⋯ → check for updates.

Versions follow semver: patch for fixes, minor for new themes or features.

## Pipeline

`.github/workflows/release.yml` runs on every `v*` tag:
build (universal) → sign with Developer ID → notarize and staple → zip → GitHub Release with notes
from the changelog → `appcast.xml` signed with the Sparkle key → tap update (`Casks/lichen.rb`
in `namecoder1/homebrew-tap`, written by `scripts/make-cask.sh`).

`.github/workflows/pages.yml` publishes `site/` to https://namecoder1.github.io/lichen/ on every
push to `main` (it skips while the repo is private). It also copies `docs/images` and the Deskland
thumbnails.

Names and identifiers live in one place: `scripts/config.sh`.

## Credentials

| What | Where | Expires / renew |
|---|---|---|
| Apple Developer Program | developer.apple.com/account | yearly (99 $). If it lapses, existing notarized builds keep working, but new releases cannot be notarized. |
| Developer ID Application certificate (`8486MUZA4P`) | login Keychain; base64 `.p12` in `MACOS_CERT_P12` + `MACOS_CERT_PASSWORD` | **2027-11-13**. Before then: create a new one, export a `.p12`, update both secrets. Notarized builds stay valid after expiry. |
| Notarization | `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (app-specific password "lichen-ci"); local notarytool profile "lichen" | Revoked if the Apple ID password changes: generate a new app-specific password at account.apple.com. |
| Sparkle EdDSA key | private: login Keychain + `SPARKLE_PRIVATE_KEY`; public: `scripts/config.sh` | Never expires. **Keep an offline backup** (`generate_keys -x file`). If lost, installed copies can no longer verify updates and users must download the next version by hand. |
| Tap token | `HOMEBREW_TAP_TOKEN` (fine-grained PAT, write access to `homebrew-tap`) | Check its expiry at github.com/settings/tokens; when it expires the release succeeds but the tap step fails. |
| `SIGN_IDENTITY` | secret | `Developer ID Application: Tobia Bartolomei (8486MUZA4P)` |

Never commit any of these; `.gitignore` already excludes `*.p12`, `*.cer`, `*.key`, `sparkle-private*.txt`.

## Deskland themes

`Resources/themes/deskland/` is an **unmodified** copy of Deskland Preview
(github.com/BLEZZ0102/Deskland, GPL-3.0) at the commit in `UPSTREAM_COMMIT`. Lichen's fixes live in
`Resources/themes/patches/<id>.js` and are injected by the host after the page loads
(`ThemeWebView.swift`). The host also emulates `window.chrome.webview` (WebView2) and throttles
`requestAnimationFrame`.

To update from upstream:
1. Clone upstream, copy the theme files over `deskland/`, write the new commit hash into `UPSTREAM_COMMIT`.
2. Check that each patch still finds the functions it redefines (e.g. `chooseMaldivesPalms`).
3. Run `scripts/bench.sh` for beach and meadow and compare with `docs/benchmarks/README.md`.
4. Keep `NOTICE` accurate. Deskland's name, logo and icon are not ours to use (see `TRADEMARKS.md`).

## Performance

`scripts/bench.sh` measures GPU use per theme and quality (about 8 minutes, don't touch the Mac).
Reference numbers (M3 Pro) are in `docs/benchmarks/README.md`; re-run after touching shaders,
`core.js`, the shim or quality settings.

## Donations

- GitHub Sponsors: github.com/sponsors/namecoder1 (tiers 🌱 2 $, 🌿 5 $, 🌳 10 $ monthly; 3/10/25 $ one-time).
- Ko-fi: ko-fi.com/namecoder1.
- Promised perks: name in the Supporters list (README + site) from 5 $/month or 10 $ one-time, if the
  sponsor wants it; theme polls in GitHub Discussions for 🌳 Grove. No paywalled features.
- Linked from `.github/FUNDING.yml`, the site (`#support`), both READMEs and the panel's ⋯ menu.
