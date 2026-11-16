# Benchmark GPU — 2026-11-15

- Mac: Apple M3 Pro · macOS 27.2
- Schermo: 3024 x 1964 Retina
- Lichen: 904627c-dirty
- Velo della luce: spento
- Riferimento (tema fermo a tutto schermo): 0% GPU · media di 8 s per riga

Tema a tutto schermo con icone finte, desktop interamente visibile (caso peggiore).
La finestra copre il resto dello schermo: "Lichen" = GPU totale meno il riferimento.

| Tema | Qualità | Scala | fps | GPU totale | Lichen |
|---|---|---|---|---|---|
| beach | high | 1.25× | 30 | 21% | **21%** |
| beach | balanced | 1.0× | 24 | 10% | **10%** |
| beach | saver | 0.75× | 20 | 8% | **8%** |
| meadow | high | 1.25× | 30 | 24% | **24%** |
| meadow | balanced | 1.0× | 24 | 15% | **15%** |
| meadow | saver | 0.75× | 20 | 10% | **10%** |
| zen | high | 2.0× | 30 | 0% | **0%** |
| zen | balanced | 1.5× | 30 | 0% | **0%** |
| zen | saver | 1.0× | 20 | 0% | **0%** |
| reef | high | 2.0× | 30 | 26% | **26%** |
| reef | balanced | 1.5× | 30 | 17% | **17%** |
| reef | saver | 1.0× | 20 | 6% | **6%** |
| pixel | high | 2.0× | 30 | 13% | **13%** |
| pixel | balanced | 1.5× | 30 | 9% | **9%** |
| pixel | saver | 1.0× | 20 | 5% | **5%** |
| topo | high | 2.0× | 30 | 0% | **0%** |
| topo | balanced | 1.5× | 30 | 0% | **0%** |
| topo | saver | 1.0× | 20 | 0% | **0%** |
| blueprint | high | 2.0× | 30 | 0% | **0%** |
| blueprint | balanced | 1.5× | 30 | 0% | **0%** |
| blueprint | saver | 1.0× | 20 | 0% | **0%** |

In uso normale Lichen va in pausa quando il desktop è visibile per meno del 15%
(GPU ≈ 0), scende a 15 fps sotto il 50% e a 10 fps dopo 90 s senza input.
