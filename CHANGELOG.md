# Changelog

All notable changes to Lichen. Versions follow [Semantic Versioning](https://semver.org).

## [0.5.0] — 2026-11-15

First public release.

### Themes
- Seven landscapes that grow around your desktop icons: Beach and Meadow (from Deskland Preview),
  Zen garden, Coral reef, Pixel RPG, Topographic and Blueprint.
- Per-theme settings (island size, palms, kayaks, clouds, zen rings…), a new landscape on demand,
  automatic rotation (hourly, daily, at launch) and a theme per display.
- Click on the desktop to send a ripple across the water.
- Daylight: golden hour, blue hour and night following the sun (estimated from the time zone,
  no location access) or the system dark appearance.

### macOS
- Menu bar panel in Control Center style (Liquid Glass on macOS 26, translucent on macOS 13–15).
- Lock screen: the theme becomes the system wallpaper, or the animated screen saver starts on lock.
- Animated screen saver (`Lichen.saver`).
- Automatic updates with Sparkle; Homebrew cask.
- Universal app (Apple Silicon and Intel), macOS 13 or later; signed and notarized.

### Performance
- Static themes use no GPU at rest.
- Animated themes pause when windows cover the desktop, slow down when it is barely visible or
  nobody is using the Mac, and render at lower resolution on battery, in Low Power Mode, on Intel
  Macs or when the Mac runs hot. Measurements in [docs/benchmarks](docs/benchmarks/README.md).

[0.5.0]: https://github.com/namecoder1/lichen/releases/tag/v0.5.0
