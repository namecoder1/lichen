# Lichen

Sfondo animato per macOS che fa crescere un paesaggio attorno alle icone del desktop.
Quando sposti, crei o cancelli un file sulla scrivania, il paesaggio si adatta. Ogni avvio
(o "Nuovo paesaggio" dal menu) genera coste, dune e solchi diversi.

Software libero sotto licenza **GPL-3.0**. Gratis, senza pubblicità, senza account.
Se ti piace, puoi sostenere il progetto con una donazione volontaria (link in arrivo).

> Lichen è un progetto indipendente per macOS ispirato a [Deskland](https://deskland.app) (Windows).
> I temi Spiaggia e Prato vengono da [Deskland Preview](https://github.com/BLEZZ0102/Deskland) (GPL-3.0).
> Lichen non è affiliato né approvato da Deskland. Vedi [NOTICE](NOTICE).

## Temi

Ogni tema cambia a ogni "Nuovo paesaggio". Sotto le icone c'è sempre la "terra".

| Tema | Idea |
|---|---|
| **Spiaggia** · **Prato** | I temi di Deskland: coste turchesi con kayak e palme; prato con nuvole, aquilone e gattino |
| **Giardino zen** | Isole di muschio, ghiaia rastrellata in anelli, rocce e foglie d'acero. Statico: zero consumi |
| **Barriera corallina** | Banchi di sabbia, coralli a colonie, caustiche e banchi di pesci |
| **Pixel RPG** | Isole in stile mappa a 16 bit con alberelli, fiori e onde a pixel |
| **Topografica** | Curve di livello, tinte altimetriche, laghi e reticolo. Statica |
| **Blueprint** | Carta da progetto con contorni quotati e disegni tecnici. Statico |

## Funzioni

- **Pannello** nella barra dei menu in stile Centro di Controllo (Liquid Glass su macOS 26+).
- **Impostazioni per tema:** cursori e interruttori (ampiezza delle isole, palme, kayak, nuvole, anelli zen…).
- **Increspature:** un clic sul desktop fa un'onda dove c'è acqua (o un segno a matita sulle mappe).
- **Luce del giorno:** tramonto dorato, ora blu e notte seguendo il sole (stimato dal fuso orario,
  senza localizzazione) oppure l'aspetto scuro di macOS.
- **Rotazione dei temi:** ogni ora, ogni giorno o a ogni avvio.
- **Un tema per monitor** con più schermi.
- **Aggiornamenti automatici** con [Sparkle](https://sparkle-project.org).
- **Schermata di blocco:** il tema (senza icone) diventa lo sfondo di sistema; spegnendo l'opzione torna quello di prima.
  In alternativa, al blocco parte il salvaschermo animato.
- **Salvaschermo animato** (`Lichen.saver`): stesso motore, con arcipelaghi che cambiano forma ogni 20 s.
  Tema fisso o casuale dalle Opzioni del salvaschermo.
- **Leggero:** i temi statici non consumano nulla a riposo; risoluzione e fps scendono su Mac Intel, a batteria,
  in Risparmio energetico o se il Mac si scalda; pausa quando una finestra copre il desktop, con il Mac bloccato,
  durante il salvaschermo e con gli schermi spenti.
- **Universale:** Apple Silicon e Intel, macOS 13 o successivo.

## Installazione

```sh
brew install --cask namecoder1/tap/lichen
```

oppure scarica lo zip dalle [Releases](https://github.com/namecoder1/lichen/releases).

## Privacy

- Al primo avvio macOS chiede il permesso **Accessibilità**: Lichen lo usa solo per leggere *dove* stanno le
  icone sulla scrivania, non i nomi né il contenuto dei file.
- L'unica connessione di rete è il controllo degli aggiornamenti (Sparkle, una volta al giorno, verso GitHub).
  Nessuna statistica, nessun account.
- I clic sul desktop vengono osservati solo per disegnare le increspature (si può disattivare).

## Come funziona

- **Host (Swift):** una finestra per schermo al livello del desktop (sotto le icone, ignora i clic) con
  una `WKWebView`. Legge le posizioni delle icone dal Finder via Accessibility API ogni 400 ms e mette in
  pausa il tema quando il desktop è coperto.
- **Temi (HTML + WebGL2):** ogni tema è una pagina in `Resources/themes`. Parla lo stesso protocollo di
  Deskland: la pagina invia `ready`, l'host invia `icons` (rettangoli in pixel fisici), `settings` (seme)
  e `pause`. Per le pagine di Deskland l'host simula `window.chrome.webview` (WebView2).
- **Campo:** per ogni punto, la distanza con segno dalla "costa" attorno alle icone (somma di gaussiane,
  deformata da rumore con seme) viene calcolata su CPU e passata allo shader, che disegna tutto alla
  risoluzione piena dello schermo.

| File | Ruolo |
|---|---|
| `Sources/Lichen/AppDelegate.swift` | Ciclo principale: finestre per schermo, icone, pause, qualità, azioni del pannello |
| `Sources/Lichen/IconReader.swift` | Posizioni delle icone dal Finder (Accessibility API) |
| `Sources/Lichen/DesktopWindow.swift` | Finestra al livello del desktop che ospita il tema |
| `Sources/Lichen/PanelView.swift`, `PanelWindow.swift` | Pannello della barra dei menu (SwiftUI) e la sua finestra |
| `Sources/Lichen/Shared/` | Codice condiviso con il salvaschermo: catalogo dei temi, WKWebView, impostazioni, qualità |
| `Saver/LichenSaverView.swift` | Salvaschermo `Lichen.saver` |
| `Resources/themes/lichen/core.js` | Motore comune dei temi Lichen (campo, rumore, morphing, protocollo) |
| `Resources/themes/lichen/*.html` | Temi Lichen: ognuno è uno shader più il posizionamento dei dettagli |
| `Resources/themes/deskland/` | Temi di Deskland, inclusi senza modifiche (commit in `UPSTREAM_COMMIT`) |

Per creare un tema: copia `zen.html`, cambia lo shader (`fieldS(p)` < 0 sotto le icone) e aggiungilo a
`ThemeCatalog.all`. Aprendo la pagina direttamente nel browser si vede un'anteprima con icone finte
(clic = nuovo seme).

## Sviluppo

```sh
swift build -c release && .build/release/Lichen   # avvio rapido (il permesso va dato al terminale)
.build/release/Lichen --dump                       # albero Accessibility del Finder
.build/release/Lichen --snapshot /tmp/out zen      # PNG dei temi con le icone attuali (--demo: icone finte)
.build/release/Lichen --thumbs Resources/thumbs    # rigenera le anteprime dei temi
.build/release/Lichen --make-icon /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
scripts/build-app.sh 0.1.0                         # dist/Lichen.app + zip
.build/release/Lichen --panel-test                 # misura la fluidità del pannello
```

## Rilasci

`scripts/config.sh` contiene nome, bundle id e repository. Un tag `vX.Y.Z` avvia
`.github/workflows/release.yml`: compila, firma, (notarizza), crea la Release e aggiorna il tap Homebrew.
I secrets necessari sono elencati in cima al workflow.

### Aggiornamenti automatici (Sparkle)

La chiave pubblica EdDSA è in `scripts/config.sh`; la privata sta nel Portachiavi del maintainer
(`generate_keys`) e, per la CI, nel secret `SPARKLE_PRIVATE_KEY`. Ogni release pubblica anche
`appcast.xml`, che l'app legge da
`https://github.com/namecoder1/lichen/releases/latest/download/appcast.xml`.

## Prossimi passi

- Altri temi: stagno con ninfee, neve
- Pile (Stacks), "Nascondi elementi della scrivania": da testare

## Licenza

[GPL-3.0-or-later](LICENSE). Crediti e marchi in [NOTICE](NOTICE).
