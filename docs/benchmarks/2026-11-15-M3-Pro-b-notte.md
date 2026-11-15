# Benchmark GPU — 2026-11-15

- Mac: Apple M3 Pro · macOS 27.2
- Schermo: 3024 x 1964 Retina
- Lichen: 904627c-dirty
- Velo della luce: -10
- Riferimento (tema fermo a tutto schermo): 0% GPU · media di 8 s per riga

Tema a tutto schermo con icone finte, desktop interamente visibile (caso peggiore).
La finestra copre il resto dello schermo: "Lichen" = GPU totale meno il riferimento.

| Tema | Qualità | Scala | fps | GPU totale | Lichen |
|---|---|---|---|---|---|
| beach | high | 1.25× | 30 | 23% | **23%** |
| meadow | high | 1.25× | 30 | 27% | **27%** |
| zen | high | 2.0× | 30 | 0% | **0%** |
| reef | high | 2.0× | 30 | 26% | **26%** |
| pixel | high | 2.0× | 30 | 14% | **14%** |
| topo | high | 2.0× | 30 | 0% | **0%** |
| blueprint | high | 2.0× | 30 | 0% | **0%** |

In uso normale Lichen va in pausa quando il desktop è visibile per meno del 15%
(GPU ≈ 0), scende a 15 fps sotto il 50% e a 10 fps dopo 90 s senza input.
