# GPU benchmark — 2026-11-15

- Mac: Apple M3 Pro · macOS 27.2
- Display: 3024 x 1964 Retina
- Lichen: 904627c-dirty
- Light tint: -10
- Baseline (static theme full screen): 0% GPU · average of 8 s per row

Theme full screen with fake icons, desktop fully visible (worst case).
The window covers the rest of the screen: "Lichen" = total GPU minus the baseline.

| Theme | Quality | Scale | fps | Total GPU | Lichen |
|---|---|---|---|---|---|
| beach | high | 1.25× | 30 | 23% | **23%** |
| meadow | high | 1.25× | 30 | 27% | **27%** |
| zen | high | 2.0× | 30 | 0% | **0%** |
| reef | high | 2.0× | 30 | 26% | **26%** |
| pixel | high | 2.0× | 30 | 14% | **14%** |
| topo | high | 2.0× | 30 | 0% | **0%** |
| blueprint | high | 2.0× | 30 | 0% | **0%** |

In normal use Lichen pauses when less than 15% of the desktop is visible
(GPU ≈ 0), drops to 15 fps below 50% and to 10 fps after 90 s without input.
