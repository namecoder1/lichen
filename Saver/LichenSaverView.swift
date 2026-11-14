import AppKit
import ScreenSaver

/// Salvaschermo animato di Lichen: lo stesso motore dei temi, senza le icone del desktop.
/// Al loro posto ci sono "arcipelaghi" invisibili che cambiano forma e posizione ogni tanto,
/// così coste, nuvole e giardini si trasformano lentamente.
@objc(LichenSaverView)
final class LichenSaverView: ScreenSaverView {
    private static let module = "io.github.namecoder1.lichen.saver"
    private var themeView: ThemeWebView?
    private var shuffleTimer: Timer?
    private var sheet: NSWindow?
    private var themePopup: NSPopUpButton?
    private var islandsCheck: NSButton?

    private var defaults: ScreenSaverDefaults? { ScreenSaverDefaults(forModuleWithName: Self.module) }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        if let res = Bundle(for: LichenSaverView.self).resourceURL { ThemeCatalog.resources = res }
        defaults?.register(defaults: ["theme": "random", "islands": true])
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1          // la pagina WebGL si anima da sola
        // macOS 14+: il processo del salvaschermo non chiama sempre stopAnimation
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(willStop),
            name: Notification.Name("com.apple.screensaver.willstop"), object: nil)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func chosenTheme() -> ThemeInfo {
        let id = defaults?.string(forKey: "theme") ?? "random"
        return id == "random" ? (ThemeCatalog.all.randomElement() ?? ThemeCatalog.all[0]) : ThemeCatalog.byId(id)
    }

    override func startAnimation() {
        super.startAnimation()
        if themeView == nil {
            let backing = window?.backingScaleFactor ?? 2
            let quality = isPreview ? RenderQuality(scale: 1, fps: 20)
                : RenderQuality(scale: SystemInfo.isIntel ? 1 : min(backing, 2), fps: 30)
            let v = ThemeWebView(frame: bounds, theme: chosenTheme(), seed: Int.random(in: 1..<1_000_000), quality: quality)
            v.autoresizingMask = [.width, .height]
            addSubview(v)
            themeView = v
        }
        themeView?.paused = false
        shuffleIslands()
        shuffleTimer?.invalidate()
        if defaults?.bool(forKey: "islands") ?? true {
            shuffleTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                self?.shuffleIslands()
            }
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        shuffleTimer?.invalidate()
        themeView?.paused = true
    }

    @objc private func willStop() {
        guard !isPreview else { return }
        shuffleTimer?.invalidate()
        themeView?.unload()
        themeView?.removeFromSuperview()
        themeView = nil
    }

    override func animateOneFrame() {}

    /// 2–4 gruppi di "icone" invisibili in punti casuali: il tema ci costruisce attorno isole, nuvole, rocce.
    private func shuffleIslands() {
        guard defaults?.bool(forKey: "islands") ?? true else { themeView?.setIcons([]); return }
        let W = bounds.width, H = bounds.height
        let k = max(0.2, W / 1440)
        let iw = 80 * k, ih = 78 * k
        var rects: [CGRect] = []
        for _ in 0..<Int.random(in: 2...4) {
            let cx = CGFloat.random(in: W * 0.1...W * 0.8), cy = CGFloat.random(in: H * 0.1...H * 0.75)
            let cols = Int.random(in: 1...3), rows = Int.random(in: 1...3)
            for c in 0..<cols {
                for r in 0..<rows where Double.random(in: 0...1) < 0.8 {
                    rects.append(CGRect(x: cx + CGFloat(c) * iw * 1.05, y: cy + CGFloat(r) * ih * 1.15, width: iw, height: ih))
                }
            }
        }
        themeView?.setIcons(rects)
    }

    // MARK: Opzioni (Impostazioni di Sistema → Salvaschermo → Opzioni…)

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if let sheet { syncSheet(); return sheet }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 170), styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView(frame: w.contentRect(forFrameRect: w.frame))

        let title = NSTextField(labelWithString: "Lichen")
        title.font = .boldSystemFont(ofSize: 15)
        title.frame = NSRect(x: 20, y: 130, width: 320, height: 22)

        let label = NSTextField(labelWithString: "Tema:")
        label.frame = NSRect(x: 20, y: 94, width: 60, height: 20)
        let popup = NSPopUpButton(frame: NSRect(x: 80, y: 89, width: 260, height: 28))
        popup.addItem(withTitle: "Casuale a ogni avvio")
        popup.lastItem?.representedObject = "random"
        popup.menu?.addItem(.separator())
        for t in ThemeCatalog.all {
            popup.addItem(withTitle: t.name)
            popup.lastItem?.representedObject = t.id
        }

        let check = NSButton(checkboxWithTitle: "Isole e nuvole che cambiano forma", target: nil, action: nil)
        check.frame = NSRect(x: 18, y: 58, width: 320, height: 22)

        let ok = NSButton(title: "Fine", target: self, action: #selector(closeSheet))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded
        ok.frame = NSRect(x: 250, y: 14, width: 90, height: 30)

        [title, label, popup, check, ok].forEach(content.addSubview)
        w.contentView = content
        sheet = w
        themePopup = popup
        islandsCheck = check
        syncSheet()
        return w
    }

    private func syncSheet() {
        let id = defaults?.string(forKey: "theme") ?? "random"
        if let item = themePopup?.itemArray.first(where: { $0.representedObject as? String == id }) {
            themePopup?.select(item)
        }
        islandsCheck?.state = (defaults?.bool(forKey: "islands") ?? true) ? .on : .off
    }

    @objc private func closeSheet() {
        if let id = themePopup?.selectedItem?.representedObject as? String { defaults?.set(id, forKey: "theme") }
        defaults?.set(islandsCheck?.state == .on, forKey: "islands")
        defaults?.synchronize()
        if let sheet { sheet.sheetParent?.endSheet(sheet) }
        // applica subito nell'anteprima
        themeView?.removeFromSuperview()
        themeView = nil
        if isAnimating { startAnimation() }
    }
}
