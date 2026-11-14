import AppKit
import WebKit

/// Qualità di disegno: risoluzione della pagina (pixel per punto) e frame al secondo massimi.
struct RenderQuality: Equatable {
    var scale: CGFloat
    var fps: Int
}

/// Vista che ospita la pagina WebGL di un tema e parla con lei (protocollo host di Deskland).
/// Condivisa tra le finestre del desktop e il salvaschermo.
final class ThemeWebView: NSView {
    private let web: WKWebView
    private let navDelegate = NavigationDelegate()
    private var ready = false
    private var lastIcons: [[Int]]?
    private var seed: Int
    private let demo: Bool
    private(set) var quality: RenderQuality
    private var settings: [String: Double] = [:]
    private var light: LightTint = .none
    /// Velo della luce del giorno: un livello nativo in "moltiplica" sopra la pagina, composto dalla GPU
    /// di sistema (prima era un elemento della pagina e costringeva WebKit a ricomporla a ogni fotogramma).
    private let tintView = NSView()
    private var pendingRipple: (CGPoint, Date)?
    private var themeID: String
    private let capture: Bool
    var paused = false { didSet { if paused != oldValue { sendPause() } } }
    var onLog: ((String) -> Void)?

    /// Script iniettato prima di ogni pagina:
    /// - finge `window.chrome.webview` (WebView2), così le pagine di Deskland girano senza modifiche;
    /// - impone `devicePixelRatio` = qualità scelta dall'host (le pagine disegnano a quella risoluzione);
    /// - inoltra gli errori JavaScript.
    private static func shim(scale: CGFloat, fps: Int) -> String {
        """
        (() => {
          let dpr = \(scale);
          try { Object.defineProperty(window, 'devicePixelRatio', { get: () => dpr, configurable: true }); } catch (e) {}
          window.__lichenFPS = \(fps);
          window.__lichenSetQuality = (s, f) => { dpr = s; window.__lichenFPS = f; dispatchEvent(new Event('resize')); };
          // Le pagine di Deskland chiedono un fotogramma a ogni refresh dello schermo (fino a 120 Hz) e
          // si limitano da sole solo a 30 fps: qui requestAnimationFrame rispetta gli fps scelti dall'host
          // e, a pagina in pausa, si sveglia 4 volte al secondo. Un timer invece del rAF a vuoto: tra un
          // fotogramma e l'altro la pagina dorme davvero. I temi Lichen gestiscono già il proprio ritmo.
          const nativeRAF = window.requestAnimationFrame.bind(window);
          const nativeCancel = window.cancelAnimationFrame.bind(window);
          let rafQueue = new Map(), rafNext = 1, rafTimer = 0, rafLast = 0, idle = false;
          const flush = t => {
            rafTimer = 0; rafLast = performance.now();
            const q = rafQueue; rafQueue = new Map();
            q.forEach(fn => { try { fn(t); } catch (e) { setTimeout(() => { throw e; }); } });
          };
          window.requestAnimationFrame = fn => {
            if (window.Lichen) return nativeRAF(fn);
            const id = rafNext++;
            rafQueue.set(id, fn);
            if (!rafTimer) {
              const interval = idle ? 250 : 1000 / (window.__lichenFPS || 30);
              const wait = Math.max(0, interval - (performance.now() - rafLast) - 4);
              rafTimer = setTimeout(() => nativeRAF(flush), wait);
            }
            return -id;
          };
          window.cancelAnimationFrame = id => { if (id < 0) rafQueue.delete(-id); else nativeCancel(id); };
          const listeners = [];
          const host = window.webkit.messageHandlers.lichen;
          window.chrome = window.chrome || {};
          window.chrome.webview = {
            postMessage: m => host.postMessage(typeof m === 'string' ? m : JSON.stringify(m)),
            addEventListener: (type, fn) => { if (type === 'message') listeners.push(fn); },
            removeEventListener: (type, fn) => { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); },
          };
          window.__lichenReceive = s => listeners.forEach(fn => fn({ data: s }));
          const log = (...a) => host.postMessage('log:' + a.join(' '));
          addEventListener('error', e => log(e.message, (e.filename || '').split('/').pop() + ':' + e.lineno));
          addEventListener('unhandledrejection', e => log('promise:', e.reason));
          // sonda: segnala i fotogrammi bloccati (pagina non in pausa) per trovare gli scatti
          let lastF = 0, hidden = false;
          window.__lichenProbe = on => { hidden = !on; idle = !on; lastF = 0; };
          const probe = t => {
            if (!hidden && lastF && t - lastF > 250) log('scatto', Math.round(t - lastF) + 'ms');
            lastF = t; requestAnimationFrame(probe);
          };
          // solo sulle pagine che ridisegnano già a ogni fotogramma (Deskland): sui temi Lichen statici
          // la sonda terrebbe sveglia la pagina a 120 Hz
          addEventListener('load', () => { if (!window.Lichen) requestAnimationFrame(probe); });
          const ce = console.error.bind(console);
          console.error = (...a) => { log(...a); ce(...a); };
        })();
        """
    }

    private static let capturePatch = """
    (() => {
      const get = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (type, opts) {
        if (type === 'webgl2' || type === 'webgl') opts = Object.assign({}, opts, { preserveDrawingBuffer: true });
        return get.call(this, type, opts);
      };
    })();
    """

    /// `capture`: vista usata solo per esportare immagini (canvas leggibile in ogni momento).
    init(frame: NSRect, theme: ThemeInfo, seed: Int, quality: RenderQuality, demo: Bool = false, capture: Bool = false,
         settings: [String: Double] = [:]) {
        self.seed = seed
        self.settings = settings
        self.demo = demo
        self.quality = quality
        self.themeID = theme.id
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ThemeSchemeHandler(), forURLScheme: ThemeSchemeHandler.scheme)
        self.capture = capture
        config.suppressesIncrementalRendering = true
        // Mission Control, Exposé, Launchpad coprono per un attimo la finestra: senza questo WebKit
        // la considera nascosta e sospende l'animazione finché non torna visibile.
        if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }
        web = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")      // niente lampo bianco al caricamento
        web.autoresizingMask = [.width, .height]
        super.init(frame: frame)
        addSubview(web)
        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        tintView.isHidden = true
        addSubview(tintView)
        config.userContentController.add(WeakMessageHandler(self), name: "lichen")
        navDelegate.onCrash = { [weak self] in
            self?.onLog?("processo web terminato, ricarico")
            self?.reload()
        }
        web.navigationDelegate = navDelegate
        load(theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Lo shim nasce con la qualità attuale: una pagina nuova (cambio tema, ricarica) parte già
    /// alla risoluzione giusta invece di quella con cui era stata creata la vista.
    private func installScripts() {
        let ucc = web.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: Self.shim(scale: quality.scale, fps: quality.fps),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if capture {
            ucc.addUserScript(WKUserScript(source: Self.capturePatch, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
    }

    func load(_ theme: ThemeInfo, settings: [String: Double] = [:]) {
        self.settings = settings
        themeID = theme.id
        ready = false
        installScripts()
        web.load(URLRequest(url: ThemeCatalog.url(for: theme, demo: demo)))
    }

    func reload() {
        ready = false
        installScripts()
        web.reload()
    }

    /// Smette di disegnare e libera la pagina (salvaschermo che si chiude).
    func unload() {
        ready = false
        web.loadHTMLString("", baseURL: nil)
    }

    func setSeed(_ value: Int) {
        seed = value
        post(["t": "settings", "v": ["seed": seed]])
    }

    /// Impostazioni del tema (cursori): la pagina le applica senza ricaricarsi.
    func setSettings(_ values: [String: Double]) {
        settings = values
        sendSettings()
    }

    /// Clic sul desktop in `p` (punti, origine in alto a sinistra): un'increspatura dove c'è acqua.
    /// Se la pagina è in pausa (finestra che copre lo schermo) l'onda parte appena riprende.
    func ripple(at p: CGPoint) {
        guard ready else { return }
        if paused { pendingRipple = (p, Date()); return }
        let x = Double(p.x), y = Double(p.y)
        post(["t": "ripple", "x": x, "y": y])
        // pagine di Deskland: stessa reazione del loro clic con il mouse
        web.evaluateJavaScript("typeof isWater === 'function' && typeof addRipple === 'function' && isWater(\(x), \(y)) && addRipple(\(x), \(y))")
    }

    /// Velo della luce del giorno; `seconds` = durata della transizione (animata da Core Animation).
    /// Il velo ideale moltiplica la pagina per m = (1 - a) + a·colore. Un filtro "moltiplica" sopra una
    /// pagina animata però obbliga il sistema a ricomporre tutto lo schermo con Core Image a ogni
    /// fotogramma (circa +12% di GPU su un M3 Pro). Qui lo stesso effetto è approssimato con una
    /// velatura normale (costo quasi nullo): scurisce quanto la media di m e aggiunge la tinta che
    /// riproduce m esattamente sui toni medi.
    static func overlayColor(for tint: LightTint) -> CGColor {
        let a = tint.alpha
        let m = tint.rgb.map { 1 - a + a * $0 }
        let alpha = max(0, 1 - m.reduce(0, +) / Double(m.count))
        guard alpha > 0.001 else { return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) }
        let g = 0.5
        let c = m.map { min(1, max(0, g * ($0 - (1 - alpha)) / alpha)) }
        return CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: alpha)
    }

    func setLight(_ tint: LightTint, seconds: Double = 60) {
        guard tint != light, let layer = tintView.layer else { return }
        light = tint
        let color = Self.overlayColor(for: tint)
        if tint.alpha <= 0.005 {
            tintView.isHidden = true
            layer.backgroundColor = color
            return
        }
        let from = tintView.isHidden ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) : (layer.presentation()?.backgroundColor ?? layer.backgroundColor)
        tintView.isHidden = false
        if seconds > 0 {
            let anim = CABasicAnimation(keyPath: "backgroundColor")
            anim.fromValue = from
            anim.toValue = color
            anim.duration = seconds
            layer.add(anim, forKey: "light")
        }
        layer.backgroundColor = color
    }

    func setQuality(_ q: RenderQuality) {
        guard q != quality else { return }
        quality = q
        web.evaluateJavaScript("window.__lichenSetQuality && window.__lichenSetQuality(\(q.scale), \(q.fps))")
        // le icone vanno rimandate nella nuova scala
        lastIcons = nil
        if let pts = lastIconsPoints { setIcons(pts) }
    }

    private var lastIconsPoints: [CGRect]?

    /// Rettangoli in punti, coordinate locali della vista con origine in alto a sinistra.
    func setIcons(_ rects: [CGRect]) {
        lastIconsPoints = rects
        let k = quality.scale
        let local = rects.map { r in [r.minX, r.minY, r.maxX, r.maxY].map { Int(($0 * k).rounded()) } }
        guard local != lastIcons else { return }
        lastIcons = local
        sendIcons()
    }

    // MARK: Messaggi

    fileprivate func pageSaid(_ body: Any) {
        if let text = body as? String, text.hasPrefix("log:") {
            onLog?("[tema] " + String(text.dropFirst(4)))
            return
        }
        guard (body as? String) == "ready" else { return }
        ready = true
        // correzioni di Lichen ai temi di Deskland (Resources/themes/patches/<id>.js), prima delle icone
        if let patch = try? String(contentsOf: ThemeCatalog.root.appendingPathComponent("patches/\(themeID).js"), encoding: .utf8) {
            web.evaluateJavaScript(patch)
        }
        sendSettings()
        sendIcons()
        sendPause()
    }

    private func sendSettings() {
        var v: [String: Any] = ["seed": seed]
        for (k, x) in settings { v[k] = x }
        post(["t": "settings", "v": v])
    }

    private func sendIcons() {
        guard let icons = lastIcons else { return }
        post(["t": "icons", "vis": true, "r": icons])
    }

    private func sendPause() {
        web.evaluateJavaScript("window.__lichenProbe && window.__lichenProbe(\(!paused))")
        if !paused, let (p, t) = pendingRipple {
            pendingRipple = nil
            if Date().timeIntervalSince(t) < 1.5 { DispatchQueue.main.async { self.ripple(at: p) } }
        }
        post(["t": "pause", "v": paused])
    }

    private func post(_ message: [String: Any]) {
        guard ready,
              let json = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: json, encoding: .utf8),
              let literal = try? JSONSerialization.data(withJSONObject: jsonString, options: .fragmentsAllowed),
              let jsLiteral = String(data: literal, encoding: .utf8)
        else { return }
        web.evaluateJavaScript("window.__lichenReceive(\(jsLiteral))")
    }

    // MARK: Cattura

    /// Immagine del tema: hook `__lichenSnapshot` per i temi Lichen; per le pagine di Deskland
    /// `__dbg.bench()` (disegno sincrono) e poi il canvas più grande; in ultima istanza lo snapshot di WebKit.
    func snapshot(_ done: @escaping (NSImage?) -> Void) {
        let js = """
        (() => {
          if (window.__lichenSnapshot) return JSON.parse(window.__lichenSnapshot(true)).img;
          try { window.__dbg && window.__dbg.bench && window.__dbg.bench(); } catch (e) {}
          const c = [...document.querySelectorAll('canvas')].sort((a, b) => b.width * b.height - a.width * a.height)[0];
          return c ? c.toDataURL('image/png') : null;
        })()
        """
        web.evaluateJavaScript(js) { [weak self] result, _ in
            if let img = result as? String, let comma = img.firstIndex(of: ","),
               let data = Data(base64Encoded: String(img[img.index(after: comma)...])),
               let image = NSImage(data: data) {
                done(image)
                return
            }
            let cfg = WKSnapshotConfiguration()
            cfg.afterScreenUpdates = true
            self?.web.takeSnapshot(with: cfg) { image, _ in done(image) }
        }
    }
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    var onCrash: (() -> Void)?
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onCrash?() }
}

/// Evita il ciclo di riferimenti WKUserContentController → handler → vista.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var view: ThemeWebView?
    init(_ view: ThemeWebView) { self.view = view }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        view?.pageSaid(message.body)
    }
}


/// Colore e intensità del velo "moltiplica" che simula la luce dell'ora del giorno.
struct LightTint: Equatable {
    var rgb: [Double]       // 0...1
    var alpha: Double       // 0 = nessun effetto
    static let none = LightTint(rgb: [1, 1, 1], alpha: 0)
}
