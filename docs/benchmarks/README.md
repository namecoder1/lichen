# GPU benchmarks

GPU use of each theme, measured with `scripts/bench.sh`: the theme full screen with fake icons and the
desktop fully visible, which is the worst case. In normal use Lichen pauses when windows leave less than
15% of the desktop visible (GPU ≈ 0), drops to 15 fps below 50% and to 10 fps after 90 s without input.

To run it again (about 8 minutes, don't touch the Mac):

```sh
scripts/bench.sh                                  # all themes, three qualities
THEMES="reef pixel" QUALITIES=high scripts/bench.sh
QUALITIES=high LIGHT=-10 scripts/bench.sh         # with the night tint
```

## Apple M3 Pro · 3024×1964 Retina · macOS 27.2 · November 2026

GPU used by Lichen (%). Maximum / Balanced / Saver are the qualities in the panel.
In Automatic, on power, the heavy animated themes use Balanced.

| Theme | Animated | Maximum | Balanced | Saver |
|---|---|---|---|---|
| Beach (Deskland) | yes | 21 | 10 | 8 |
| Meadow (Deskland) | yes | 24 | 15 | 10 |
| Coral reef | yes | 13 | 8 | 8 |
| Pixel RPG | yes | 6 | 3 | 6 |
| Zen garden | no | 0 | 0 | 0 |
| Topographic | no | 0 | 0 | 0 |
| Blueprint | no | 0 | 0 | 0 |

Measurement noise is about ±3 points. The night tint adds about 2 points.

### Before

| Situation | Lichen |
|---|---|
| 0.4.0 · Beach, Maximum (2×, 30 fps), Core Image "multiply" tint, no pause behind windows | ~40% always |
| Coral reef, Maximum (2×) | 26% |
| Pixel RPG, Maximum (2×, 30 fps) | 13% |

What made the difference: lower resolution for heavy themes (pixel count grows with the square of the
scale), host-side fps caps for the Deskland pages too, a light tint without Core Image filters, pausing
based on the coverage of all windows, and Pixel RPG drawn at 1× and 12 fps with nearest-neighbour scaling.

The `YYYY-MM-DD-*.md` files are the raw reports:
- `a-day`: all themes, three qualities, before the Coral reef and Pixel RPG changes
- `b-night`: Maximum with the night tint
- `c-reef-pixel`: Coral reef and Pixel RPG after the changes
