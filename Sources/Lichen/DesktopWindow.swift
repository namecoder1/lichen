import AppKit

/// Finestra senza bordi al livello del desktop (sopra lo sfondo di sistema, sotto le icone del Finder,
/// trasparente ai clic, in tutti gli Spaces) che ospita la pagina WebGL del tema.
final class DesktopWindow: NSWindow {
    private(set) var targetScreen: NSScreen
    let themeView: ThemeWebView
    private(set) var theme: ThemeInfo

    var paused: Bool {
        get { themeView.paused }
        set { themeView.paused = newValue }
    }

    init(screen: NSScreen, theme: ThemeInfo, seed: Int, quality: RenderQuality,
         demo: Bool = false, capture: Bool = false, settings: [String: Double] = [:]) {
        targetScreen = screen
        self.theme = theme
        themeView = ThemeWebView(frame: NSRect(origin: .zero, size: screen.frame.size), theme: theme, seed: seed,
                                 quality: quality, demo: demo, capture: capture, settings: settings)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = themeView
        setFrame(screen.frame, display: false)
        themeView.onLog = { NSLog("%@", $0) }
    }

    var displayID: CGDirectDisplayID? { targetScreen.displayID }

    /// Lo schermo ha cambiato dimensione o posizione: si adatta senza ricaricare la pagina.
    func move(to screen: NSScreen) {
        targetScreen = screen
        setFrame(screen.frame, display: true)
    }

    func load(_ theme: ThemeInfo, settings: [String: Double]) {
        self.theme = theme
        themeView.load(theme, settings: settings)
    }
    func setSettings(_ values: [String: Double]) { themeView.setSettings(values) }
    func setLight(_ tint: LightTint, seconds: Double = 60) { themeView.setLight(tint, seconds: seconds) }

    /// `p` in coordinate Cocoa globali: increspatura se il punto cade su questo schermo.
    func ripple(atScreenPoint p: NSPoint) {
        let f = targetScreen.frame
        guard f.contains(p) else { return }
        themeView.ripple(at: CGPoint(x: p.x - f.minX, y: f.maxY - p.y))
    }
    func reload() { themeView.reload() }
    func setSeed(_ value: Int) { themeView.setSeed(value) }
    func setQuality(_ q: RenderQuality) { themeView.setQuality(q) }
    func snapshot(_ done: @escaping (NSImage?) -> Void) { themeView.snapshot(done) }

    /// `rects` in coordinate AX globali (punti, origine in alto a sinistra dello schermo principale).
    func updateIcons(_ rects: [CGRect]) {
        let f = targetScreen.cgFrame
        let local = rects
            .map { $0.offsetBy(dx: -f.minX, dy: -f.minY) }
            .filter { CGRect(origin: .zero, size: f.size).contains(CGPoint(x: $0.midX, y: $0.midY)) }
        themeView.setIcons(local)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Frame in coordinate Quartz/AX: origine in alto a sinistra dello schermo principale, y verso il basso.
    var cgFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
