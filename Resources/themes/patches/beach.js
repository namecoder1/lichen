// Lichen — correzioni al tema Spiaggia di Deskland (deskland/beach-palms.js resta invariato).
// L'host esegue questo file dopo il caricamento della pagina; ridefinisce una funzione globale.
// Derivato da Deskland Preview (GPL-3.0); modificato per Lichen, GPL-3.0.
//
// Palme stabili: in origine, a ogni spostamento di icona le palme venivano riscelte da zero su tutte
// le isole, quindi sparivano e ricomparivano altrove anche lontano dall'icona spostata. Qui le palme
// che stanno ancora bene dove sono restano ferme; si cercano posti nuovi solo per quelle che non
// vanno più bene (finite in acqua o sotto un'icona) e per quelle che mancano.
(() => {
  if (typeof chooseMaldivesPalms !== 'function' || typeof BEACH_PALM_STYLES === 'undefined') return;

  const SHORE_MIN = -58, SHORE_MAX = -25;

  function crownOf(style, p) {
    return {x: p.x + style.crown[0] * p.scale * p.mirror, y: p.y + style.crown[1] * p.scale};
  }

  function stillFits(p) {
    const style = BEACH_PALM_STYLES[p.variant];
    if (!style) return false;
    const radius = style.radius * p.scale;
    const shore = sampleArr(FB.s, p.x, p.y);
    if (shore > SHORE_MAX || shore < SHORE_MIN) return false;
    if (p.y >= H - TASKBAR - 55 * p.scale || p.x < radius + 5 || p.x > W - radius - 5) return false;
    const crown = crownOf(style, p);
    if (crown.x < radius + 3 || crown.x > W - radius - 3 || crown.y < radius + 3) return false;
    return beachPalmClear(p.x, p.y - 16 * p.scale, 10 * p.scale) && beachPalmClear(crown.x, crown.y, radius);
  }

  chooseMaldivesPalms = function () {
    const scene = beachPalmsScene;
    const sameWorld = scene && scene.seed === seed && scene.width === W && scene.height === H;
    const kept = [];
    if (sameWorld) {
      for (const p of scene.palms) {
        if (p.retiring || !stillFits(p)) continue;
        kept.push({x: p.x, y: p.y, scale: p.scale, variant: p.variant, mirror: p.mirror, opacity: 0, retiring: false});
      }
    }

    // Stesso procedimento dell'originale per i posti liberi, distanziati anche dalle palme tenute.
    const random = mulberry32((seed ^ 0x41fc72 ^ (kept.length * 0x9e37)) >>> 0), chosen = kept.slice();
    const order = BEACH_PALM_STYLES.map((_, i) => i);
    for (let i = order.length - 1; i > 0; i--) {const j = Math.floor(random() * (i + 1));[order[i], order[j]] = [order[j], order[i]];}
    const styleRandom = mulberry32((seed ^ 0x6ac309) >>> 0);
    while (order.length < 10) order.push(Math.floor(styleRandom() * BEACH_PALM_STYLES.length));
    for (const variant of order) {
      if (chosen.length >= 10) break;
      const style = BEACH_PALM_STYLES[variant], spacing = 60 + random() * 35;
      const scale = .62 * .80 * (style.size || 1);
      const radius = style.radius * scale, offsetX = random() * 13, offsetY = random() * 13;
      let best = null, candidates = 0;
      for (let y = 100 * scale + offsetY; y < H - TASKBAR - 55 * scale; y += 13) for (let x = radius + 5 + offsetX; x < W - radius - 5; x += 13) {
        const shore = sampleArr(FB.s, x, y);
        if (shore > SHORE_MAX || shore < SHORE_MIN) continue;
        if (chosen.some(q => Math.hypot(q.x - x, q.y - y) < spacing)) continue;
        const seaX = style.faceSea ? sampleArr(FB.s, x + 8, y) - sampleArr(FB.s, x - 8, y) : 0;
        const mirror = style.faceSea && seaX * style.crown[0] < 0 ? -1 : 1;
        const crown = {x: x + style.crown[0] * scale * mirror, y: y + style.crown[1] * scale};
        if (crown.x < radius + 3 || crown.x > W - radius - 3) continue;
        if (crown.y < radius + 3 || !beachPalmClear(x, y - 16 * scale, 10 * scale) || !beachPalmClear(crown.x, crown.y, radius)) continue;
        if (random() < 1 / ++candidates) best = {x, y, scale, variant, mirror, opacity: 0, retiring: false};
      }
      if (best) chosen.push(best);
    }
    return chosen;
  };
})();
