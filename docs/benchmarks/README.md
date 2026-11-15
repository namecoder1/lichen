# Benchmark GPU

Uso della GPU dei temi, misurato con `scripts/bench.sh`: tema a tutto schermo con icone finte e
desktop interamente visibile, cioè il caso peggiore. Nell'uso normale Lichen va in pausa quando le
finestre lasciano scoperto meno del 15% del desktop (GPU ≈ 0), scende a 15 fps sotto il 50% e a
10 fps dopo 90 s senza input.

Per rifarlo (circa 8 minuti, senza toccare il Mac):

```sh
scripts/bench.sh                                  # tutti i temi, tre qualità
THEMES="reef pixel" QUALITIES=high scripts/bench.sh
QUALITIES=high LIGHT=-10 scripts/bench.sh         # con il velo della notte
```

## Apple M3 Pro · 3024×1964 Retina · macOS 27.2 · novembre 2026

GPU usata da Lichen (%). Massima / Bilanciata / Risparmio sono le qualità del pannello.
In Automatica, con l'alimentatore collegato, i temi animati pesanti usano Bilanciata.

| Tema | Animato | Massima | Bilanciata | Risparmio |
|---|---|---|---|---|
| Spiaggia (Deskland) | sì | 21 | 10 | 8 |
| Prato (Deskland) | sì | 24 | 15 | 10 |
| Barriera corallina | sì | 13 | 8 | 8 |
| Pixel RPG | sì | 6 | 3 | 6 |
| Giardino zen | no | 0 | 0 | 0 |
| Topografica | no | 0 | 0 | 0 |
| Blueprint | no | 0 | 0 | 0 |

Il rumore di misura è di circa ±3 punti. Il velo della luce (notte) aggiunge circa 2 punti.

### Com'era prima

| Situazione | Lichen |
|---|---|
| 0.4.0 · Spiaggia, Massima (2×, 30 fps), velo "moltiplica" di Core Image, nessuna pausa con più finestre | ~40% sempre |
| Barriera corallina, Massima (2×) | 26% |
| Pixel RPG, Massima (2×, 30 fps) | 13% |

Cosa ha fatto la differenza: risoluzione ridotta per i temi pesanti (i pixel crescono col quadrato
della scala), fps limitati dall'host anche per le pagine di Deskland, velo della luce senza filtri
Core Image, pausa calcolata sulla copertura di tutte le finestre, Pixel RPG disegnato a 1× e 12 fps
con ingrandimento senza sfumature.

I file `AAAA-MM-GG-*.md` sono i report grezzi:
- `a-giorno`: tutti i temi, tre qualità, prima delle modifiche a Barriera corallina e Pixel RPG
- `b-notte`: Massima con il velo della notte
- `c-reef-pixel`: Barriera corallina e Pixel RPG dopo le modifiche
