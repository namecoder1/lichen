/*
 * Lichen — motore comune dei temi (WebGL2, risoluzione piena dello schermo).
 * Copyright (C) 2026 Lichen contributors — GPL-3.0-or-later.
 *
 * Il campo "distanza dalla costa" (somma di gaussiane della distanza dai rettangoli delle icone,
 * con domain warp e trasformazione logaritmica) segue l'approccio di Deskland
 * (https://github.com/BLEZZ0102/Deskland, GPL-3.0).
 *
 * Un tema chiama Lichen.start({ fragment, staticFragment?, sigma, warp, coast, animated, params?, extraRects?, place?, uniforms?,
 *                               maxScale?, maxFps?, pixelated? }).
 * `params`: { chiave: { def, field? } } — impostazioni regolabili dall'host ({t:'settings', v:{chiave: valore}});
 * ogni parametro arriva allo shader come `uniform float uP_<chiave>` e ai callback come api.P.<chiave>.
 * Il parametro speciale `sigma` regola la distanza della "costa" dalle icone.
 * Con staticFragment la parte costosa (terreno) viene disegnata in una texture solo quando il campo cambia;
 * `fragment` gira a ogni frame e legge quel livello con staticColor(), aggiungendo solo ciò che si muove.
 * Lo shader del tema riceve dal preludio: cssPos(), fieldS(p) (px, <0 sotto le icone), fieldGrad(p),
 * tex(p, scala) (rumore tileable a 4 canali), hash12, vnoise, fbm, uTime, uSeed, uScale.
 *
 * Protocollo host (uguale a Deskland): la pagina invia "ready"; riceve
 *   {t:'icons', vis, r:[[l,t,r,b]...]} in pixel fisici · {t:'settings', v:{seed, ...params}} · {t:'pause', v} · {t:'ripple', x, y} (px CSS)
 */
'use strict';
(() => {
  const QS = new URLSearchParams(location.search);
  const HOSTED = QS.has('wallpaper');
  const STEP = 4;          // passo della griglia del campo, in px CSS
  const MORPH_MS = 1600;   // durata della trasformazione quando le icone si spostano

  const VS = `#version 300 es
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

  const PRELUDE = `#version 300 es
precision highp float;
uniform sampler2D uFA, uFB, uNoise, uStatic;
uniform vec2 uView, uGrid;
uniform float uScale, uMix, uTime, uSeed, uStep;
uniform vec4 uIcon[64];      // icone: centro x, y, mezza larghezza, mezza altezza (px CSS)
uniform int uIconN;
uniform vec4 uRipple[6];     // clic sul desktop: x, y, età (s), attivo
out vec4 outColor;
vec2 cssPos() { vec2 f = gl_FragCoord.xy / uScale; return vec2(f.x, uView.y - f.y); }
vec2 fieldUV(vec2 p) { return (p / uStep + 0.5) / uGrid; }
float fieldS(vec2 p) { vec2 uv = fieldUV(p); return mix(texture(uFA, uv).r, texture(uFB, uv).r, uMix); }
vec2 fieldGrad(vec2 p) {
  float e = uStep;
  return vec2(fieldS(p + vec2(e, 0.)) - fieldS(p - vec2(e, 0.)),
              fieldS(p + vec2(0., e)) - fieldS(p - vec2(0., e))) / (2.0 * e);
}
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec4 tex(vec2 p, float scale) { return texture(uNoise, p / scale); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p), u = f * f * (3. - 2. * f);
  return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float s = 0., a = .5; for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.03 + 17.1; a *= .5; } return s; }
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
vec3 staticColor() { return texelFetch(uStatic, ivec2(gl_FragCoord.xy), 0).rgb; }
vec4 staticTexel() { return texelFetch(uStatic, ivec2(gl_FragCoord.xy), 0); }   // .a = maschera del tema
vec3 hsv(float h, float s, float v) { vec3 k = clamp(abs(mod(h * 6. + vec3(0., 4., 2.), 6.) - 3.) - 1., 0., 1.); return v * mix(vec3(1.), k, s); }
vec2 hash22(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
// Voronoi: x = distanza dal centro più vicino, y = F2 - F1 (≈ distanza dal bordo), z = id casuale della cella
vec3 voronoi(vec2 p) {
  vec2 n = floor(p), f = fract(p); float d1 = 8., d2 = 8.; vec2 id = n;
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 g = vec2(i, j), r = g + hash22(n + g) - f; float d = dot(r, r);
    if (d < d1) { d2 = d1; d1 = d; id = n + g; } else if (d < d2) d2 = d;
  }
  return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), hash12(id));
}
// Increspature dei clic: onda con segno (per deformare/ombreggiare) e anello positivo (per disegnare).
float ripple(vec2 p) {
  float acc = 0.0;
  for (int i = 0; i < 6; i++) {
    vec4 r = uRipple[i];
    if (r.w < 0.5) continue;
    float d = length(p - r.xy), R = r.z * 120.0;
    float env = exp(-pow((d - R) / 16.0, 2.0)) * (1.0 - smoothstep(0.0, 2.2, r.z));
    acc += env * sin((d - R) * 0.45);
  }
  return acc;
}
float rippleRing(vec2 p) {
  float acc = 0.0;
  for (int i = 0; i < 6; i++) {
    vec4 r = uRipple[i];
    if (r.w < 0.5) continue;
    float d = length(p - r.xy), R = r.z * 120.0;
    acc += exp(-pow((d - R) / 3.0, 2.0)) * (1.0 - smoothstep(0.0, 2.2, r.z))
         + 0.5 * exp(-pow((d - R * 0.62) / 2.5, 2.0)) * (1.0 - smoothstep(0.0, 1.6, r.z));
  }
  return clamp(acc, 0.0, 1.0);
}
float aastep(float e, float x) { float w = max(fwidth(x), 1e-4) * 0.75; return smoothstep(e - w, e + w, x); }
// linea sottile di larghezza w (px) dove la funzione x vale 0
float aaline(float x, float w) { float d = abs(x) / max(fwidth(x), 1e-4); return 1.0 - smoothstep(w * 0.5, w * 0.5 + 1.0, d); }
`;

  function mulberry32(a) {
    return () => {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // float32 → float16 (per le texture R16F, filtrabili linearmente ovunque)
  const f32 = new Float32Array(1), u32 = new Uint32Array(f32.buffer);
  function toHalf(v) {
    f32[0] = v;
    const x = u32[0], sign = (x >>> 16) & 0x8000, e = ((x >>> 23) & 0xff) - 112;
    if (e <= 0) return sign;
    if (e >= 31) return sign | 0x7bff;
    return sign | (e << 10) | ((x & 0x7fffff) >>> 13);
  }

  function start(T) {
    const PARAMS = Object.assign({ sigma: { def: T.sigma ?? 70, field: true } }, T.params || {});
    const P = {};
    for (const k in PARAMS) P[k] = PARAMS[k].def;
    const warpAmp = T.warp ?? 30, coast = T.coast ?? 1.0;
    const ripples = [];   // {x, y, t0}

    document.documentElement.style.cssText = 'margin:0;height:100%;overflow:hidden';
    document.body.style.cssText = `margin:0;height:100%;overflow:hidden;background:${T.background || '#000'}`;
    const cv = document.createElement('canvas');
    cv.style.cssText = 'display:block;width:100vw;height:100vh';
    // pixel art: la pagina disegna a bassa risoluzione e lo schermo ingrandisce senza sfumare
    if (T.pixelated) cv.style.imageRendering = 'pixelated';
    document.body.appendChild(cv);
    const gl = cv.getContext('webgl2', { antialias: false, alpha: false });
    if (!gl) { document.body.textContent = 'WebGL2 non disponibile'; return; }

    let seed = (Math.random() * 1e6) | 0;
    let W = 0, H = 0, dpr = 1, Gw = 1, Gh = 1;
    let warpX = null, warpY = null;
    let icons = [], seen = !HOSTED, paused = false, dirty = true;
    let sA = null, sB = null, mixT0 = -1e9;
    const state = {};   // spazio libero per i temi (rocce, foglie, palme…)

    // ---------- rumore CPU (con seme) ----------
    function hash2(x, y, k) {
      let h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(seed + k, 2246822519);
      h = Math.imul(h ^ (h >>> 13), 1274126177);
      return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
    }
    function vnoise(x, y, k, px = 0, py = 0) {
      const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
      const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
      const w = (v, p) => p ? ((v % p) + p) % p : v;
      const x0 = w(ix, px), x1 = w(ix + 1, px), y0 = w(iy, py), y1 = w(iy + 1, py);
      const a = hash2(x0, y0, k), b = hash2(x1, y0, k), c = hash2(x0, y1, k), d = hash2(x1, y1, k);
      return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
    }
    function fbm(x, y, k) {
      let a = 0.5, s = 0;
      for (let i = 0; i < 4; i++) { s += a * vnoise(x, y, k + i * 7); x = x * 2.03 + 17.1; y = y * 2.03 + 17.1; a *= 0.5; }
      return s;
    }

    // ---------- WebGL ----------
    function compile(type, src) {
      const sh = gl.createShader(type);
      gl.shaderSource(sh, src); gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh));
      return sh;
    }
    function link(fs) {
      const pr = gl.createProgram();
      gl.attachShader(pr, compile(gl.VERTEX_SHADER, VS));
      gl.attachShader(pr, compile(gl.FRAGMENT_SHADER, PRELUDE + Object.keys(P).map(k => `uniform float uP_${k};\n`).join('') + fs));
      gl.linkProgram(pr);
      if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(pr));
      const cache = {};
      return { pr, u: n => (n in cache ? cache[n] : (cache[n] = gl.getUniformLocation(pr, n))) };
    }
    const main = link(T.fragment);
    const stat = T.staticFragment ? link(T.staticFragment) : null;
    let tS = null, fbo = null, staticDirty = true;
    function allocStatic() {
      if (!stat) return;
      if (tS) gl.deleteTexture(tS);
      if (!fbo) fbo = gl.createFramebuffer();
      tS = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tS);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, cv.width, cv.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tS, 0);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      staticDirty = true;
    }

    function makeTex(filter, wrap) {
      const t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter === 'mip' ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
      return t;
    }
    const tA = makeTex('lin', gl.CLAMP_TO_EDGE), tB = makeTex('lin', gl.CLAMP_TO_EDGE);
    const tN = makeTex('mip', gl.REPEAT);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);

    // Rumore tileable 256×256, 4 canali a frequenze diverse: dettaglio "organico" nello shader.
    function buildNoiseTex() {
      const S = 256, d = new Uint8Array(S * S * 4);
      const periods = [[8, 16, 32, 64], [4, 8, 16, 32], [16, 32, 64], [32, 64, 128]];
      for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
        for (let c = 0; c < 4; c++) {
          let s = 0, w = 0.5, tw = 0;
          for (let i = 0; i < periods[c].length; i++) {
            const p = periods[c][i];
            s += w * vnoise(x / S * p, y / S * p, 100 + c * 50 + i * 13, p, p); tw += w; w *= 0.5;
          }
          d[(y * S + x) * 4 + c] = Math.min(Math.max((s / tw - 0.5) * 1.9 + 0.5, 0), 1) * 255;
        }
      }
      gl.bindTexture(gl.TEXTURE_2D, tN);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, S, S, 0, gl.RGBA, gl.UNSIGNED_BYTE, d);
      gl.generateMipmap(gl.TEXTURE_2D);
    }

    function buildWarp() {
      const N = Gw * Gh;
      warpX = new Float32Array(N); warpY = new Float32Array(N);
      for (let gy = 0; gy < Gh; gy++) for (let gx = 0; gx < Gw; gx++) {
        const i = gy * Gw + gx, x = gx * STEP, y = gy * STEP;
        warpX[i] = fbm(x * 0.0028, y * 0.0028, 1) - 0.47;
        warpY[i] = fbm(x * 0.0028, y * 0.0028, 2) - 0.47;
      }
    }

    // ---------- campo: s = distanza con segno dalla "costa" (px CSS, < 0 sotto le icone) ----------
    function computeField(rects) {
      const N = Gw * Gh, f = new Float32Array(N);
      const sigma = P.sigma, is2 = 1 / (sigma * sigma), wa = warpAmp * 2.2;
      for (const r of rects) {
        const R = 5.5 * sigma + Math.max(r.hw, r.hh) + wa;
        const gx0 = Math.max(0, Math.floor((r.cx - R) / STEP)), gx1 = Math.min(Gw - 1, Math.ceil((r.cx + R) / STEP));
        const gy0 = Math.max(0, Math.floor((r.cy - R) / STEP)), gy1 = Math.min(Gh - 1, Math.ceil((r.cy + R) / STEP));
        const chw = r.hw * 0.5, chh = r.hh * 0.5;
        for (let gy = gy0; gy <= gy1; gy++) for (let gx = gx0; gx <= gx1; gx++) {
          const i = gy * Gw + gx;
          const qx = gx * STEP + warpX[i] * wa, qy = gy * STEP + warpY[i] * wa;
          let dx = Math.abs(qx - r.cx) - chw, dy = Math.abs(qy - r.cy) - chh;
          if (dx < 0) dx = 0; if (dy < 0) dy = 0;
          f[i] += Math.exp(-(dx * dx + dy * dy) * is2);
        }
      }
      const s = new Float32Array(N), fMin = Math.exp(-30);
      for (let i = 0; i < N; i++) {
        const g = Math.log(Math.max(f[i], fMin));
        s[i] = sigma * (Math.sqrt(Math.max(-g, 0)) - coast) - sigma * 0.6 * Math.max(g, 0);
      }
      return s;
    }

    function upload(tex, s) {
      const h = new Uint16Array(s.length);
      for (let i = 0; i < s.length; i++) h[i] = toHalf(s[i]);
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.R16F, Gw, Gh, 0, gl.RED, gl.HALF_FLOAT, h);
    }

    const ease = t => t * t * (3 - 2 * t);
    const curMix = (now = performance.now()) => ease(Math.min(Math.max((now - mixT0) / MORPH_MS, 0), 1));

    function sampleS(x, y) {
      if (!sB) return 999;
      const fx = Math.min(Math.max(x / STEP, 0), Gw - 1.001), fy = Math.min(Math.max(y / STEP, 0), Gh - 1.001);
      const ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy, i = iy * Gw + ix;
      return (sB[i] * (1 - tx) + sB[i + 1] * tx) * (1 - ty) + (sB[i + Gw] * (1 - tx) + sB[i + Gw + 1] * tx) * ty;
    }

    const api = {
      get W() { return W; }, get H() { return H; }, get icons() { return icons; },
      state, sampleS, P,
      rng: k => mulberry32(Math.imul(seed, 31) + k),   // generatore stabile per lo stesso seme
      // Punti casuali lontani dalle icone e tra loro (colline, rocce, pianeti…).
      scatter(k, count, { fromIcons = 260, apart = 280, margin = 100, tries = 400 } = {}) {
        const rng = api.rng(k), out = [];
        for (let t = 0; t < tries && out.length < count; t++) {
          const x = margin + rng() * (W - 2 * margin), y = margin + rng() * (H - 2 * margin);
          if (icons.some(ic => Math.hypot(ic.x + ic.w / 2 - x, ic.y + ic.h / 2 - y) < fromIcons)) continue;
          if (out.some(o => Math.hypot(o.x - x, o.y - y) < apart)) continue;
          out.push({ x, y, r: rng(), k: rng() * 1000 });
        }
        return out;
      },
    };

    function iconRects() {
      return icons.map(ic => ({ cx: ic.x + ic.w / 2, cy: ic.y + ic.h / 2, hw: ic.w / 2, hh: ic.h / 2 }));
    }

    function commit(fromEmpty) {
      const extra = T.extraRects ? T.extraRects(api) : [];
      const next = computeField(iconRects().concat(extra));
      if (fromEmpty || !sB) {
        sA = computeField([]);
      } else {
        const m = curMix();                      // si riparte da dove si era arrivati
        if (m < 1) { const b = new Float32Array(sA.length); for (let i = 0; i < b.length; i++) b[i] = sA[i] + (sB[i] - sA[i]) * m; sA = b; }
        else sA = sB;
      }
      sB = next;
      upload(tA, sA); upload(tB, sB);
      mixT0 = performance.now();
      if (T.place) T.place(api);
      dirty = true; staticDirty = true;
      wake();
    }

    function resize() {
      // maxScale: un tema può disegnare a meno pixel della qualità scelta (pixel art, immagini morbide)
      W = innerWidth; H = innerHeight; dpr = Math.min(devicePixelRatio || 1, T.maxScale || Infinity);
      cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
      Gw = Math.ceil(W / STEP) + 2; Gh = Math.ceil(H / STEP) + 2;
      allocStatic();
      buildWarp();
      sB = null;
      commit(true);
    }

    function applySettings(v) {
      let field = false, changed = false;
      for (const k in v) {
        if (k === 'seed' || !(k in PARAMS) || typeof v[k] !== 'number' || P[k] === v[k]) continue;
        P[k] = v[k]; changed = true;
        if (PARAMS[k].field) field = true;
      }
      if (typeof v.seed === 'number' && v.seed !== seed) { reseed(v.seed); return; }
      if (field) commit(false);
      else if (changed) { if (T.place) T.place(api); dirty = true; staticDirty = true; }
    }

    function reseed(v) {
      seed = v;
      buildNoiseTex(); buildWarp();
      commit(true);
    }

    function pass(PR, now) {
      const u = PR.u;
      gl.useProgram(PR.pr);
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, tA); gl.uniform1i(u('uFA'), 0);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, tB); gl.uniform1i(u('uFB'), 1);
      gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, tN); gl.uniform1i(u('uNoise'), 2);
      gl.uniform2f(u('uView'), W, H);
      gl.uniform2f(u('uGrid'), Gw, Gh);
      gl.uniform1f(u('uScale'), dpr);
      gl.uniform1f(u('uStep'), STEP);
      gl.uniform1f(u('uMix'), curMix(now));
      gl.uniform1f(u('uTime'), (now / 1000) % 3600);
      gl.uniform1f(u('uSeed'), (seed % 1000) * 0.1);
      const ic = new Float32Array(64 * 4);
      icons.slice(0, 64).forEach((c, i) => ic.set([c.x + c.w / 2, c.y + c.h / 2, c.w / 2, c.h / 2], i * 4));
      gl.uniform4fv(u('uIcon'), ic); gl.uniform1i(u('uIconN'), Math.min(icons.length, 64));
      for (const k in P) { const l = u('uP_' + k); if (l) gl.uniform1f(l, P[k]); }
      const rp = new Float32Array(24);
      ripples.forEach((r, i) => rp.set([r.x, r.y, (now - r.t0) / 1000, 1], i * 4));
      gl.uniform4fv(u('uRipple'), rp);
      if (T.uniforms) T.uniforms(gl, u, now, api);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    function draw(now) {
      gl.viewport(0, 0, cv.width, cv.height);
      const morphing = now - mixT0 < MORPH_MS + 100;
      if (stat && (staticDirty || morphing)) {
        gl.activeTexture(gl.TEXTURE3); gl.bindTexture(gl.TEXTURE_2D, null);   // niente feedback loop
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        pass(stat, now);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        staticDirty = false;
      }
      if (stat) { gl.activeTexture(gl.TEXTURE3); gl.bindTexture(gl.TEXTURE_2D, tS); }
      gl.useProgram(main.pr); gl.uniform1i(main.u('uStatic'), 3);
      pass(main, now);
    }

    let last = 0, frames = 0;
    // Per gli snapshot dell'host: disegna e legge il canvas nello stesso task (non serve preserveDrawingBuffer).
    window.__lichenSnapshot = (settle) => {
      if (settle) mixT0 = -1e9;                 // salta la trasformazione: immagine finale
      staticDirty = true; draw(performance.now());
      return JSON.stringify({ frames, img: cv.toDataURL('image/png') });
    };
    // Il ciclo di disegno gira solo quando serve: temi statici e pause non svegliano la pagina,
    // i temi animati chiedono il fotogramma successivo solo quando è il momento (30 fps su schermi a 120 Hz).
    let scheduled = false;
    function wake(delay = 0) {
      if (scheduled) return;
      scheduled = true;
      if (delay > 4) setTimeout(() => requestAnimationFrame(frame), delay);
      else requestAnimationFrame(frame);
    }
    function frame(now) {
      scheduled = false;
      frames++;
      const hadRipples = ripples.length > 0;
      while (ripples.length && now - ripples[0].t0 > 2300) ripples.shift();
      if (hadRipples) dirty = true;          // l'ultimo fotogramma cancella l'onda
      const morphing = now - mixT0 < MORPH_MS + 100;
      // maxFps: un tema che cambia a scatti (pixel art a 4–6 fps) non ha bisogno di 30 fotogrammi
      const interval = 1000 / Math.min(window.__lichenFPS || 30, T.maxFps || Infinity);
      if (dirty || morphing || ripples.length) {
        // onde e crescita del paesaggio: fluide ma al massimo 60 fps (non 120 sugli schermi ProMotion)
        if (!dirty && now - last < 1000 / 60 - 3) { wake(); return; }
        last = now; dirty = false;
        draw(now);
        wake();
        return;
      }
      if (paused || !T.animated) return;     // fermo: riparte con wake() al prossimo messaggio
      if (now - last >= interval - 3) { last = now; draw(now); }
      wake(Math.max(0, interval - (performance.now() - last) - 8));
    }

    // ---------- avvio ----------
    buildNoiseTex();
    resize();
    let resizeT = 0;
    addEventListener('resize', () => { clearTimeout(resizeT); resizeT = setTimeout(resize, 100); });

    function handle(m) {
      handleMessage(m);
      wake();
    }
    function handleMessage(m) {
      if (m.t === 'pause') { paused = !!m.v; return; }
      if (m.t === 'settings') { applySettings(m.v || {}); return; }
      if (m.t === 'ripple') {
        ripples.push({ x: m.x, y: m.y, t0: performance.now() });
        if (ripples.length > 6) ripples.shift();
        dirty = true;
        return;
      }
      if (m.t !== 'icons') return;
      const k = devicePixelRatio || 1;       // letto ora: l'host può aver appena cambiato la qualità
      icons = m.vis ? m.r.map(([l, t, r, b]) => ({ x: l / k, y: t / k, w: (r - l) / k, h: (b - t) / k })) : [];
      const first = !seen; seen = true;
      commit(first);                         // la prima volta il paesaggio "cresce" dal vuoto
    }

    if (HOSTED && window.chrome && window.chrome.webview) {
      window.chrome.webview.addEventListener('message', ev => handle(JSON.parse(ev.data)));
      window.chrome.webview.postMessage('ready');
    } else if (QS.has('embed') && window.parent !== window) {
      // Demo del sito (iframe): la pagina madre manda gli stessi messaggi dell'host con postMessage
      addEventListener('message', ev => {
        if (ev.source === window.parent && ev.data && typeof ev.data.t === 'string') handle(ev.data);
      });
      window.parent.postMessage('lichen-ready', '*');
    } else {
      // Anteprima nel browser: icone finte in colonna a destra (come il Finder) e qualcuna in mezzo.
      const demo = [];
      for (let i = 0; i < 7; i++) demo.push({ x: W - 100, y: 40 + i * 92, w: 80, h: 78 });
      for (let i = 0; i < 4; i++) demo.push({ x: W - 190, y: 40 + i * 92, w: 80, h: 78 });
      demo.push({ x: W * 0.35, y: H * 0.45, w: 80, h: 78 }, { x: W * 0.35 + 90, y: H * 0.45, w: 80, h: 78 });
      icons = demo; commit(true);
      addEventListener('click', () => reseed((Math.random() * 1e6) | 0));
    }
    wake();
  }

  window.Lichen = { start };
})();
