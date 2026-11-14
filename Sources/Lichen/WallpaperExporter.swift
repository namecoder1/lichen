import AppKit

/// Renderizza il tema SENZA icone (niente isole, nuvole sulle icone, ecc.) e lo imposta come
/// sfondo di sistema: è quello che macOS mostra nella schermata di blocco.
@MainActor
final class WallpaperExporter {
    static let shared = WallpaperExporter()

    private var window: DesktopWindow?
    private var pending: [(screen: NSScreen, theme: ThemeInfo, seed: Int, done: (NSImage?) -> Void)] = []
    private var running = false

    private let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Lichen/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Una finestra di cattura alla volta, dietro alle finestre del desktop (invisibile all'utente).
    func render(screen: NSScreen, theme: ThemeInfo, seed: Int, done: @escaping (NSImage?) -> Void) {
        pending.append((screen, theme, seed, done))
        next()
    }

    private func next() {
        guard !running, !pending.isEmpty else { return }
        running = true
        let job = pending.removeFirst()
        let w = DesktopWindow(screen: job.screen, theme: job.theme, seed: job.seed,
                              quality: RenderQuality(scale: job.screen.backingScaleFactor, fps: 30), capture: true,
                              settings: ThemeSettingsStore.values(for: job.theme))
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        w.orderFront(nil)
        w.updateIcons([])           // nessuna icona: solo il "mare" del tema
        window = w
        // tempo per caricare pagina e immagini (palme, gatto, ecc.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            w.snapshot { image in
                w.orderOut(nil)
                self?.window = nil
                self?.running = false
                job.done(image)
                self?.next()
            }
        }
    }

    // MARK: Sfondo di sistema (schermata di blocco)

    /// Imposta il tema come immagine di sfondo di ogni schermo; ricorda gli sfondi originali.
    func applyLockScreen(themeFor: (NSScreen) -> ThemeInfo, seed: Int, completion: @escaping () -> Void) {
        let screens = NSScreen.screens
        var remaining = screens.count
        saveOriginalsIfNeeded()
        for screen in screens {
            let theme = themeFor(screen)
            render(screen: screen, theme: theme, seed: seed) { [weak self] image in
                defer { remaining -= 1; if remaining == 0 { completion() } }
                guard let self, let image, let id = screen.displayID else { return }
                // nome unico: macOS mette in cache gli sfondi per URL
                let url = self.folder.appendingPathComponent("\(theme.id)-\(seed)-\(id)-\(Int(Date().timeIntervalSince1970)).png")
                guard self.writePNG(image, to: url) else { return }
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                self.cleanup(keeping: url, display: id)
            }
        }
        if screens.isEmpty { completion() }
    }

    func restoreOriginals() {
        let saved = UserDefaults.standard.dictionary(forKey: "originalWallpapers") as? [String: String] ?? [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let path = saved["\(id)"] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        UserDefaults.standard.removeObject(forKey: "originalWallpapers")
    }

    private func saveOriginalsIfNeeded() {
        var saved = UserDefaults.standard.dictionary(forKey: "originalWallpapers") as? [String: String] ?? [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID, saved["\(id)"] == nil,
                  let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  !url.path.hasPrefix(folder.path) else { continue }
            saved["\(id)"] = url.path
        }
        UserDefaults.standard.set(saved, forKey: "originalWallpapers")
    }

    private func cleanup(keeping keep: URL, display: CGDirectDisplayID) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f != keep && f.lastPathComponent.contains("-\(display)-") {
            try? FileManager.default.removeItem(at: f)
        }
    }

    private func writePNG(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
