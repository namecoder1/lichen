# Lichen — notes for Claude

macOS menu-bar app (Swift + SwiftPM, macOS 13+, universal) that shows an animated wallpaper
growing around the desktop icons. GPL-3.0, free, donations only. Read `README.md` (architecture
table) and `docs/MAINTAINING.md` (releases, credentials, upstream) before larger changes.

## Build and run
```sh
swift build -c release && .build/release/Lichen          # needs Accessibility for the terminal
.build/release/Lichen --snapshot /tmp/out zen --demo     # PNG of a theme with fake icons
QUALITY=high|balanced|saver HOLD=1 .build/debug/Lichen --snapshot DIR THEME --demo   # dev knobs
scripts/build-app.sh X.Y.Z                               # dist/Lichen.app (+ Lichen.saver)
scripts/bench.sh                                         # GPU benchmark
```
There is no test suite: verify with `--snapshot`, `--panel-test`, `--attention` and a built app.

## Rules
- `Resources/themes/deskland/` stays byte-identical to upstream. Fixes go in
  `Resources/themes/patches/<id>.js`. Don't run Deskland pages yourself; ask the maintainer to.
- Lichen themes (`Resources/themes/lichen/*.html`) share `core.js`; register new ones in
  `ThemeCatalog.all` and add a thumbnail (`--thumbs Resources/thumbs`).
- Keep macOS 13 working: check SF Symbol availability and guard APIs with `#available`.
  The panel uses Liquid Glass only on macOS 26+.
- Performance matters: animated themes must respect host fps/scale caps and pause when hidden.
  Re-run `scripts/bench.sh` after shader or quality changes.
- UI strings are English in code, wrapped in `L("...")` (`Shared/L10n.swift`); the Italian translation is
  `Resources/it.lproj/Localizable.strings`. Add every new UI string there too. Docs, README, changelog,
  commits and the cask are English.
- Every user-visible change gets a line under a new `## [X.Y.Z]` section in `CHANGELOG.md`
  (it becomes the release notes).
- Never commit or read secrets (`*.p12`, Sparkle private key, `.env`). Releases happen only
  through tags and CI; don't tag without the maintainer's go-ahead.
