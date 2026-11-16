# GPU benchmark — 2026-11-15

- Mac: Apple M3 Pro · macOS 27.2
- Display: 3024 x 1964 Retina
- Lichen: 904627c-dirty
- Light tint: off
- Baseline (static theme full screen): 0% GPU · average of 8 s per row

Theme full screen with fake icons, desktop fully visible (worst case).
The window covers the rest of the screen: "Lichen" = total GPU minus the baseline.

| Theme | Quality | Scale | fps | Total GPU | Lichen |
|---|---|---|---|---|---|
| reef | high | 1.25× | 30 | 13% | **13%** |
| reef | balanced | 1.0× | 24 | 8% | **8%** |
| reef | saver | 0.75× | 20 | 8% | **8%** |
| pixel | high | 2.0× | 30 | 6% | **6%** |
| pixel | balanced | 1.5× | 30 | 3% | **3%** |
| pixel | saver | 1.0× | 20 | 6% | **6%** |

In normal use Lichen pauses when less than 15% of the desktop is visible
(GPU ≈ 0), drops to 15 fps below 50% and to 10 fps after 90 s without input.
