#!/bin/bash
# Benchmark GPU dei temi: per ogni tema e qualità apre il tema a tutto schermo (icone finte),
# misura l'uso della GPU e lo confronta con un tema fermo nella stessa finestra.
#
#   scripts/bench.sh                          tutti i temi, qualità high/balanced/saver
#   THEMES="zen reef" scripts/bench.sh        solo alcuni temi
#   QUALITIES="high" LIGHT=-10 scripts/bench.sh   con il velo della notte
#
# Scrive il risultato in docs/benchmarks/<data>-<chip>.md. Chiude Lichen se è aperto e lo riapre alla fine.
# Durante la misura non toccare il Mac: anche il resto dello schermo pesa sulla GPU.
set -euo pipefail
cd "$(dirname "$0")/.."

THEMES="${THEMES:-beach meadow zen reef pixel topo blueprint}"
QUALITIES="${QUALITIES:-high balanced saver}"
WARMUP="${WARMUP:-6}"      # secondi per caricare il tema e far crescere il paesaggio
SAMPLES="${SAMPLES:-8}"    # campioni, uno al secondo

gpu() { ioreg -r -d 1 -w 0 -c IOAccelerator | grep -o '"Device Utilization %"=[0-9]*' | head -1 | grep -o '[0-9]*$'; }
measure() {   # media di $SAMPLES campioni
  local sum=0 v
  for _ in $(seq "$SAMPLES"); do v=$(gpu); sum=$((sum + v)); sleep 1; done
  echo $((sum / SAMPLES))
}

swift build -q 2>&1 | grep -v "^$" || true
BIN=.build/debug/Lichen
OUT_DIR="$(mktemp -d)"

# Lichen aperto? se ne ricorda il percorso per riaprirlo alla fine
RUNNING_APP=""
if PID0=$(pgrep -x Lichen | head -1); then
  RUNNING_APP=$(ps -o comm= -p "$PID0" | sed 's|/Contents/MacOS/Lichen$||')
  osascript -e 'quit app "Lichen"'; sleep 3
fi

# Riferimento: la finestra del tema copre tutto lo schermo, quindi il resto non viene ridisegnato.
# Si misura la stessa finestra con un tema fermo (zen): quello che resta è il lavoro fisso del sistema.
echo "▸ Riferimento: finestra a tutto schermo con un tema fermo"
QUALITY=saver HOLD=1 "$BIN" --snapshot "$OUT_DIR" zen --demo >/dev/null 2>&1 &
PID=$!; sleep "$WARMUP"; BASE=$(measure); kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null || true; sleep 2
echo "  GPU $BASE%"

CHIP=$(sysctl -n machdep.cpu.brand_string)
RES=$(system_profiler SPDisplaysDataType | awk -F': ' '/Resolution/{print $2; exit}')
STAMP=$(date +%Y-%m-%d)
REPORT="docs/benchmarks/$STAMP-$(echo "$CHIP" | tr ' ' '-' | tr -cd 'A-Za-z0-9-').md"
mkdir -p docs/benchmarks

{
  echo "# Benchmark GPU — $STAMP"
  echo
  echo "- Mac: $CHIP · macOS $(sw_vers -productVersion)"
  echo "- Schermo: $RES"
  echo "- Lichen: $(git describe --always --dirty 2>/dev/null || echo '?')"
  echo "- Velo della luce: ${LIGHT:-spento}"
  echo "- Riferimento (tema fermo a tutto schermo): $BASE% GPU · media di $SAMPLES s per riga"
  echo
  echo "Tema a tutto schermo con icone finte, desktop interamente visibile (caso peggiore)."
  echo "La finestra copre il resto dello schermo: \"Lichen\" = GPU totale meno il riferimento."
  echo
  echo "| Tema | Qualità | Scala | fps | GPU totale | Lichen |"
  echo "|---|---|---|---|---|---|"
} > "$REPORT"

for t in $THEMES; do
  for q in $QUALITIES; do
    printf "▸ %-10s %-9s " "$t" "$q"
    env QUALITY="$q" HOLD=1 ${LIGHT:+LIGHT=$LIGHT} "$BIN" --snapshot "$OUT_DIR" "$t" --demo >"$OUT_DIR/out.txt" 2>/dev/null &
    PID=$!
    sleep "$WARMUP"
    G=$(measure)
    kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null || true
    D=$((G - BASE)); [ "$D" -lt 0 ] && D=0
    read -r S F < <(awk '/^qualità:/{print $2, $3; exit}' "$OUT_DIR/out.txt") || true
    S="${S:-?}×"; F="${F:-?}"
    echo "GPU $G% · Lichen $D%"
    echo "| $t | $q | $S | $F | $G% | **$D%** |" >> "$REPORT"
    sleep 2
  done
done

{
  echo
  echo "In uso normale Lichen va in pausa quando il desktop è visibile per meno del 15%"
  echo "(GPU ≈ 0), scende a 15 fps sotto il 50% e a 10 fps dopo 90 s senza input."
} >> "$REPORT"

if [ -n "$RUNNING_APP" ]; then open "$RUNNING_APP" || true; fi
echo
echo "▸ Risultato: $REPORT"
