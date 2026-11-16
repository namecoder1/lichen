import AppKit
import SwiftUI

// Strumenti da riga di comando per lo sviluppo (non usati dall'app normale):
//   --snapshot <cartella> [id ...] [--demo]   PNG di ogni tema
//   --thumbs <cartella> [id ...]              anteprime dei temi Lichen per il pannello
//   --attention                               quota di desktop visibile e inattività
//   --panel-test                              misura i blocchi del thread principale del pannello
//                                             (THEME=<id>, STAY=main|settings|back per catturarlo)

/// `--snapshot <cartella> [id ...] [--demo]`: un PNG per tema (con le icone attuali o con icone finte).
/// `--thumbs <cartella>`: anteprime dei temi Lichen (icone finte) per il pannello.
final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    let dir: URL
    let demo: Bool
    let thumbs: Bool
    var queue: [ThemeInfo]
    var current: DesktopWindow?

    init(dir: URL, ids: [String], demo: Bool, thumbs: Bool = false) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.demo = demo
        self.thumbs = thumbs
        let all = thumbs ? ThemeCatalog.all.filter { $0.credit == nil } : ThemeCatalog.all
        queue = ids.isEmpty ? all : all.filter { ids.contains($0.id) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) { next() }

    private func next() {
        current?.orderOut(nil)
        guard !queue.isEmpty, let screen = NSScreen.screens.first else { exit(0) }
        let theme = queue.removeFirst()
        // I temi di Lichen aperti senza host disegnano da soli icone finte; quelli di Deskland no,
        // quindi in --demo ricevono dall'host le stesse icone finte (disposte come in core.js).
        let pageDemo = demo && theme.credit == nil
        let w = DesktopWindow(screen: screen, theme: theme, seed: Int.random(in: 1..<1_000_000),
                              quality: Self.envQuality(screen, theme: theme), demo: pageDemo)
        w.orderFront(nil)
        if !pageDemo { w.updateIcons(demo ? Self.fakeIcons(screen) : IconReader.readIconRects()) }
        current = w
        // LIGHT=<altezza del sole>: velo della luce; stampa il numero della finestra per la cattura
        // HOLD=1: resta aperto in primo piano (per misurare, vedi scripts/bench.sh)
        let env = ProcessInfo.processInfo.environment
        let light = env["LIGHT"].flatMap(Double.init)
        if let e = light { w.themeView.setLight(SunLight.tint(elevation: e), seconds: 0) }
        if light != nil || env["HOLD"] != nil {
            w.level = .floating
            let q = w.themeView.quality
            print("quality:", q.scale, q.fps); fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { print("finestra:", w.windowNumber); fflush(stdout) }
            return
        }
        // WAIT=<secondi>: attesa prima dello scatto (predefinita 5)
        DispatchQueue.main.asyncAfter(deadline: .now() + (env["WAIT"].flatMap(Double.init) ?? 5)) {
            w.snapshot { image in
                if let image {
                    let out = self.thumbs ? Self.thumbnail(image) : image
                    let type: NSBitmapImageRep.FileType = self.thumbs ? .jpeg : .png
                    let url = self.dir.appendingPathComponent("\(theme.id).\(self.thumbs ? "jpg" : "png")")
                    if let tiff = out.tiffRepresentation,
                       let data = NSBitmapImageRep(data: tiff)?.representation(using: type, properties: [.compressionFactor: 0.82]) {
                        try? data.write(to: url)
                        print(url.path)
                    }
                } else {
                    print("snapshot fallito: \(theme.id)")
                }
                self.next()
            }
        }
    }

    /// Icone finte in coordinate globali (punti, origine in alto a sinistra): due colonne a destra
    /// come nel Finder e due icone in mezzo, come l'anteprima di core.js.
    static func fakeIcons(_ screen: NSScreen) -> [CGRect] {
        let f = screen.cgFrame, W = f.width, H = f.height
        var r: [CGRect] = []
        for i in 0..<7 { r.append(CGRect(x: W - 100, y: 40 + CGFloat(i) * 92, width: 80, height: 78)) }
        for i in 0..<4 { r.append(CGRect(x: W - 190, y: 40 + CGFloat(i) * 92, width: 80, height: 78)) }
        r.append(CGRect(x: W * 0.35, y: H * 0.45, width: 80, height: 78))
        r.append(CGRect(x: W * 0.35 + 90, y: H * 0.45, width: 80, height: 78))
        return r.map { $0.offsetBy(dx: f.minX, dy: f.minY) }
    }

    /// QUALITY=high|balanced|saver: la qualità che l'app sceglierebbe per quel tema;
    /// oppure SCALE=<x> FPS=<n>; predefinita: risoluzione dello schermo, 30 fps.
    static func envQuality(_ screen: NSScreen, theme: ThemeInfo) -> RenderQuality {
        let env = ProcessInfo.processInfo.environment
        if let mode = env["QUALITY"].flatMap(QualityMode.init(rawValue:)) {
            return QualityPolicy.decide(mode: mode, backingScale: screen.backingScaleFactor, heavy: theme.heavy).quality
        }
        return RenderQuality(scale: env["SCALE"].flatMap(Double.init).map { CGFloat($0) } ?? screen.backingScaleFactor,
                             fps: env["FPS"].flatMap(Int.init) ?? 30)
    }

    /// Ritaglio 16:10 attorno alla colonna di icone a destra, 480×300.
    static func thumbnail(_ image: NSImage) -> NSImage {
        let out = NSImage(size: NSSize(width: 480, height: 300))
        out.lockFocus()
        let src = image.size
        let cropW = src.width * 0.5, cropH = cropW * 300 / 480
        let rect = NSRect(x: src.width - cropW, y: src.height - cropH, width: cropW, height: cropH)
        image.draw(in: NSRect(x: 0, y: 0, width: 480, height: 300), from: rect, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

/// `--panel-test`: apre il pannello senza sfondi, cambia pagina 10 volte e misura i blocchi del thread principale.
final class PanelTestDelegate: NSObject, NSApplicationDelegate, AppActions {
    var model: AppModel!
    var panel: PanelController!
    var item: NSStatusItem!
    var last = CACurrentMediaTime()
    var gaps: [Double] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            model = AppModel(theme: ThemeCatalog.byId(ProcessInfo.processInfo.environment["THEME"] ?? "zen"))
            model.actions = self
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: nil)
            let tc = CACurrentMediaTime()
            panel = PanelController(model: model)
            print(String(format: "costruzione: %.0f ms", (CACurrentMediaTime() - tc) * 1000))
            let t0 = CACurrentMediaTime() + 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.panel.show(from: self.item.button!) }
            print(String(format: "apertura: %.0f ms", (CACurrentMediaTime() - t0) * 1000))
            // sonda: un timer a 120 Hz; un ritardo lungo = thread principale bloccato
            Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let now = CACurrentMediaTime(); let gap = (now - self.last) * 1000
                    if gap > 50 { print(String(format: "  blocco %.0f ms a t=%.2f s (pagina %@)", gap, now - t0, "\(self.model.page)")) }
                    self.gaps.append(gap); self.last = now
                }
            }
            var n = 0
            if let stay = ProcessInfo.processInfo.environment["STAY"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    MainActor.assumeIsolated {
                        if stay == "settings" || stay == "back" { withAnimation { self.model.page = .settings } }
                        if stay == "back" {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation { self.model.page = .main } }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            let n = NSApp.windows.filter { $0.isVisible && $0 is FloatingPanel }.map(\.windowNumber)
                            print("finestra:", n.first ?? 0, "misura:", self.model.panelSize); fflush(stdout)
                        }
                    }
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { t in
                MainActor.assumeIsolated {
                    n += 1
                    if n > 10 {
                        t.invalidate()
                        let g = self.gaps.sorted()
                        print(String(format: "campioni %d · mediana %.1f ms · p95 %.1f ms · max %.1f ms · >50ms: %d",
                                     g.count, g[g.count / 2], g[Int(Double(g.count) * 0.95)], g.last ?? 0, g.filter { $0 > 50 }.count))
                        print("misura pannello:", self.model.panelSize)
                        exit(0)
                    }
                    let t0 = CACurrentMediaTime()
                    let next: PanelPage = self.model.page == .main ? .settings : .main
                    if ProcessInfo.processInfo.environment["NOANIM"] != nil { self.model.page = next }
                    else { withAnimation(.snappy) { self.model.page = next } }
                    print(String(format: "pagina %@: %.0f ms", "\(self.model.page)", (CACurrentMediaTime() - t0) * 1000))
                }
            }
            }
        }
    }
    func selectTheme(_ theme: ThemeInfo) {}
    func newLandscape() {}
    func setPaused(_ paused: Bool) {}
    func reloadTheme() {}
    func setLockMode(_ mode: LockMode) {}
    func setShowInDock(_ on: Bool) {}
    func setQualityMode(_ mode: QualityMode) {}
    func installScreenSaver() {}
    func startScreenSaver() {}
    func openAccessibilitySettings() {}
    func setThemeSetting(_ key: String, value: Double) {}
    func resetThemeSettings() {}
    func setTargetDisplay(_ id: CGDirectDisplayID?) {}
    func setLightMode(_ mode: LightMode) {}
    func setRotation(_ mode: RotationMode) {}
    func setRipples(_ on: Bool) {}
    func checkForUpdates() {}
    func closePanel() {}
}
