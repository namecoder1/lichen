#!/bin/bash
# GPU benchmark of the themes: for each theme and quality, opens the theme full screen (fake icons),
# measures GPU use and compares it with a static theme in the same window.
#
#   scripts/bench.sh                          all themes, qualities high/balanced/saver
#   THEMES="zen reef" scripts/bench.sh        only some themes
#   QUALITIES="high" LIGHT=-10 scripts/bench.sh   with the night tint
#
# Writes the result to docs/benchmarks/<date>-<chip>.md. Quits Lichen if it's running and reopens it at the end.
# Don't touch the Mac while it measures: the rest of the screen also costs GPU.
set -euo pipefail
cd "$(dirname "$0")/.."

THEMES="${THEMES:-beach meadow zen reef pixel topo blueprint}"
QUALITIES="${QUALITIES:-high balanced saver}"
WARMUP="${WARMUP:-6}"      # seconds to load the theme and let the landscape grow
SAMPLES="${SAMPLES:-8}"    # samples, one per second

gpu() { ioreg -r -d 1 -w 0 -c IOAccelerator | grep -o '"Device Utilization %"=[0-9]*' | head -1 | grep -o '[0-9]*$'; }
measure() {   # average of $SAMPLES samples
  local sum=0 v
  for _ in $(seq "$SAMPLES"); do v=$(gpu); sum=$((sum + v)); sleep 1; done
  echo $((sum / SAMPLES))
}

swift build -q 2>&1 | grep -v "^$" || true
BIN=.build/debug/Lichen
OUT_DIR="$(mktemp -d)"

# Is Lichen running? Remember its path to reopen it at the end
RUNNING_APP=""
if PID0=$(pgrep -x Lichen | head -1); then
  RUNNING_APP=$(ps -o comm= -p "$PID0" | sed 's|/Contents/MacOS/Lichen$||')
  osascript -e 'quit app "Lichen"'; sleep 3
fi

# Baseline: the theme window covers the whole screen, so nothing else gets redrawn.
# Measure the same window with a static theme (zen): what remains is the system's fixed work.
echo "▸ Baseline: full-screen window with a static theme"
QUALITY=saver HOLD=1 "$BIN" --snapshot "$OUT_DIR" zen --demo >/dev/null 2>&1 &
PID=$!; sleep "$WARMUP"; BASE=$(measure); kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null || true; sleep 2
echo "  GPU $BASE%"

CHIP=$(sysctl -n machdep.cpu.brand_string)
RES=$(system_profiler SPDisplaysDataType | awk -F': ' '/Resolution/{print $2; exit}')
STAMP=$(date +%Y-%m-%d)
REPORT="docs/benchmarks/$STAMP-$(echo "$CHIP" | tr ' ' '-' | tr -cd 'A-Za-z0-9-').md"
mkdir -p docs/benchmarks

{
  echo "# GPU benchmark — $STAMP"
  echo
  echo "- Mac: $CHIP · macOS $(sw_vers -productVersion)"
  echo "- Display: $RES"
  echo "- Lichen: $(git describe --always --dirty 2>/dev/null || echo '?')"
  echo "- Light tint: ${LIGHT:-off}"
  echo "- Baseline (static theme full screen): $BASE% GPU · average of $SAMPLES s per row"
  echo
  echo "Theme full screen with fake icons, desktop fully visible (worst case)."
  echo "The window covers the rest of the screen: \"Lichen\" = total GPU minus the baseline."
  echo
  echo "| Theme | Quality | Scale | fps | Total GPU | Lichen |"
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
    read -r S F < <(awk '/^quality:/{print $2, $3; exit}' "$OUT_DIR/out.txt") || true
    S="${S:-?}×"; F="${F:-?}"
    echo "GPU $G% · Lichen $D%"
    echo "| $t | $q | $S | $F | $G% | **$D%** |" >> "$REPORT"
    sleep 2
  done
done

{
  echo
  echo "In normal use Lichen pauses when less than 15% of the desktop is visible"
  echo "(GPU ≈ 0), drops to 15 fps below 50% and to 10 fps after 90 s without input."
} >> "$REPORT"

if [ -n "$RUNNING_APP" ]; then open "$RUNNING_APP" || true; fi
echo
echo "▸ Result: $REPORT"
