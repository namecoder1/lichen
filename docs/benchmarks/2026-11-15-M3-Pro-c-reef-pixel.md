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
| reef | high | 1.25× | 30 | 13% | **13%** |
| reef | balanced | 1.0× | 24 | 8% | **8%** |
| reef | saver | 0.75× | 20 | 8% | **8%** |
| pixel | high | 2.0× | 30 | 6% | **6%** |
| pixel | balanced | 1.5× | 30 | 3% | **3%** |
| pixel | saver | 1.0× | 20 | 6% | **6%** |

In uso normale Lichen va in pausa quando il desktop è visibile per meno del 15%
(GPU ≈ 0), scende a 15 fps sotto il 50% e a 10 fps dopo 90 s senza input.
