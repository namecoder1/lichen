import AppKit
import Sparkle
import SwiftUI

/// Rileva gli schermi coperti da una finestra a schermo intero o massimizzata (come fa Deskland su Windows).
/// Usa solo i rettangoli delle finestre, che non richiedono il permesso di registrazione schermo.
enum CoverDetector {
    /// Quota di ogni schermo lasciata scoperta dalle finestre normali (0 = tutto coperto, 1 = desktop libero).
    /// Si sommano tutte le finestre, non solo la più grande: due finestre affiancate coprono lo schermo
    /// quanto una a tutto schermo. Calcolo su una griglia di 64×40 celle, che basta e costa poco.
    static func visibleFraction(_ screens: [NSScreen]) -> [CGDirectDisplayID: Double] {
        var out: [CGDirectDisplayID: Double] = [:]
        for s in screens { if let id = s.displayID { out[id] = 1 } }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return out }
        let me = ProcessInfo.processInfo.processIdentifier
        // finestre di sistema temporanee (Mission Control, Exposé, Stage Manager, centro notifiche…)
        let system: Set<String> = ["Dock", "WindowManager", "Window Server", "Control Center", "Centro di Controllo",
                                   "NotificationCenter", "Notification Center", "Centro Notifiche", "screencaptureui",
                                   "Spotlight", "loginwindow", "ScreenSaverEngine"]
        var rects: [CGRect] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  !system.contains(w[kCGWindowOwnerName as String] as? String ?? ""),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.5,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b), rect.width > 40, rect.height > 40
            else { continue }
            rects.append(rect)
        }
        let cols = 64, rows = 40
        for s in screens {
            guard let id = s.displayID else { continue }
            let sf = s.cgFrame
            let mine = rects.compactMap { r -> CGRect? in let i = r.intersection(sf); return i.isNull ? nil : i }
            guard !mine.isEmpty else { continue }
            var covered = 0
            for row in 0..<rows {
                let y = sf.minY + (Double(row) + 0.5) * sf.height / Double(rows)
                for col in 0..<cols {
                    let x = sf.minX + (Double(col) + 0.5) * sf.width / Double(cols)
                    if mine.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { covered += 1 }
                }
            }
            out[id] = 1 - Double(covered) / Double(cols * rows)
        }
        return out
    }
}

/// Quanto conta l'animazione in questo momento: piena, a ritmo ridotto o ferma.
enum Attention {
    /// Sotto questa quota di desktop visibile si va in pausa (dopo 2 s).
    static let hiddenBelow = 0.15
    /// Sotto questa quota il desktop si vede poco: metà degli fps.
    static let glimpseBelow = 0.5
    /// Nessun input da tastiera, mouse o trackpad da tanto: nessuno sta guardando, 10 fps.
    static let idleAfter: TimeInterval = 90

    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static func fpsCap(visible: Double, idle: TimeInterval) -> Int? {
        if idle > idleAfter { return 10 }
        if visible < glimpseBelow { return 15 }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, AppActions {
    private let defaults = UserDefaults.standard
    private var seed: Int
    private let model: AppModel
    private var windows: [DesktopWindow] = []
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private var manualPause = false
    private var timer: Timer?
    private var slowTimer: Timer?
    private let axQueue = DispatchQueue(label: "lichen.ax", qos: .utility)
    private var polling = false
    private var lastTrusted: Bool?
    private var lockScreenWork: DispatchWorkItem?
    private var settingsWork: DispatchWorkItem?
    private var lastQualityCheck = Date.distantPast
    private var lastIconRects: [CGRect] = []
    /// Da quando ogni schermo risulta coperto: si mette in pausa solo dopo un paio di secondi,
    /// così le coperture di passaggio non interrompono l'animazione.
    private var coveredSince: [CGDirectDisplayID: Date] = [:]
    /// Tetto agli fps per schermo (desktop poco visibile, utente lontano); nil = nessun tetto.
    private var fpsCaps: [CGDirectDisplayID: Int] = [:]
    /// Ultima decisione di qualità per schermo (calcolarla interroga batteria e temperatura: non a ogni giro).
    private var decisions: [CGDirectDisplayID: QualityPolicy.Decision] = [:]
    /// Schermo bloccato, salvaschermo, monitor spenti o utente cambiato: il desktop non si vede.
    private var hiddenReasons = Set<String>()
    private var pollTick = 0
    private var allPaused = false
    private var clickMonitor: Any?
    private var updater: SPUStandardUpdaterController?

    static let quitNotification = Notification.Name("io.github.namecoder1.lichen.quit")

    /// Tema di base (tutti gli schermi senza un tema proprio).
    private var globalTheme: ThemeInfo
    /// Temi scelti per singoli schermi: displayID → id del tema.
    private var themeByDisplay: [String: String]

    override init() {
        let d = UserDefaults.standard
        globalTheme = ThemeCatalog.byId(d.string(forKey: "theme"))
        themeByDisplay = d.dictionary(forKey: "themeByDisplay") as? [String: String] ?? [:]
        model = AppModel(theme: globalTheme)
        let saved = d.integer(forKey: "seed")
        seed = saved != 0 ? saved : Int.random(in: 1..<1_000_000)
        super.init()
        defaults.set(seed, forKey: "seed")
        model.actions = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Una sola istanza: chi parte per ultimo chiede alle altre di chiudersi.
        let dnc = DistributedNotificationCenter.default()
        let pid = "\(ProcessInfo.processInfo.processIdentifier)"
        dnc.addObserver(forName: Self.quitNotification, object: nil, queue: .main) { note in
            if note.object as? String != pid { NSApp.terminate(nil) }
        }
        dnc.postNotificationName(Self.quitNotification, object: pid, userInfo: nil, deliverImmediately: true)
        // aspetto chiaro/scuro cambiato: aggiorna la luce
        // Mac bloccato: niente disegno finché non si sblocca; con "Salvaschermo al blocco" parte il salvaschermo
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setHidden("lock", true); self?.macLocked() }
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setHidden("lock", false) }
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setHidden("saver", true) }
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setHidden("saver", false) }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for (name, key, on) in [(NSWorkspace.screensDidSleepNotification, "display", true),
                                (NSWorkspace.screensDidWakeNotification, "display", false),
                                (NSWorkspace.sessionDidResignActiveNotification, "session", true),
                                (NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
                                (NSWorkspace.willSleepNotification, "sleep", true),
                                (NSWorkspace.didWakeNotification, "sleep", false)] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setHidden(key, on) }
            }
        }
        dnc.addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.applyLight() }
        }

        setupUpdater()
        setupStatusItem()
        applyDockPolicy()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        if model.rotation == .launch { rotateTheme() } else { rotateIfDue() }
        syncWindows()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyQuality() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLight(); self?.rotateIfDue() }
        }

        // Come Deskland: controllo ogni 400 ms, la pagina riceve solo i cambiamenti.
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduledPoll() }
        }
        timer?.tolerance = 0.1
        // Luce del giorno e rotazione dei temi: basta una volta al minuto.
        slowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLight(); self?.rotateIfDue() }
        }
        slowTimer?.tolerance = 10
        poll()
        applyRipples()
        if model.lockScreen { scheduleLockScreen(delay: 4) }
    }

    /// Clic sull'icona nel Dock (se visibile): apre il pannello.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePanel(nil)
        return false
    }

    // MARK: Aggiornamenti (Sparkle)

    /// Attivo solo nelle build pubblicate (Info.plist con SUFeedURL e SUPublicEDKey).
    private func setupUpdater() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let key = info["SUPublicEDKey"] as? String, !key.isEmpty, info["SUFeedURL"] != nil else { return }
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        model.canCheckForUpdates = true
    }

    func checkForUpdates() {
        Haptics.tap()
        panel.close()
        NSApp.activate(ignoringOtherApps: true)
        updater?.checkForUpdates(nil)
    }

    // MARK: Barra dei menu e pannello

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.action = #selector(togglePanel(_:))
        statusItem.button?.target = self
        updateStatusIcon()
        panel = PanelController(model: model)
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if !panel.isShown {
            model.refreshSaverInstalled()
            refreshScreens()
        }
        panel.toggle(from: button)
    }

    func closePanel() { panel.close() }

    private func updateStatusIcon() {
        let name = model.trusted ? globalTheme.symbol : "exclamationmark.triangle"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Lichen")
            ?? NSImage(systemSymbolName: "leaf", accessibilityDescription: "Lichen")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    // MARK: Temi per schermo

    private func theme(for screen: NSScreen) -> ThemeInfo {
        guard let id = screen.displayID, let own = themeByDisplay["\(id)"] else { return globalTheme }
        return ThemeCatalog.byId(own)
    }

    /// Il tema mostrato nel pannello: quello dello schermo scelto, o quello di base.
    private func shownTheme() -> ThemeInfo {
        guard let target = model.targetDisplay, let own = themeByDisplay["\(target)"] else { return globalTheme }
        return ThemeCatalog.byId(own)
    }

    private func refreshScreens() {
        let list = NSScreen.screens.compactMap { s in s.displayID.map { ScreenChoice(id: $0, name: s.localizedName) } }
        if model.screens != list { model.screens = list }
        if let t = model.targetDisplay, !list.contains(where: { $0.id == t }) { model.targetDisplay = nil }
        showTheme(shownTheme())
    }

    private func showTheme(_ t: ThemeInfo) {
        if model.theme.id != t.id { model.theme = t }
        model.themeSettings = ThemeSettingsStore.values(for: t)
    }

    private func saveThemes() {
        defaults.set(globalTheme.id, forKey: "theme")
        defaults.set(themeByDisplay, forKey: "themeByDisplay")
    }

    /// Ricarica solo le finestre il cui tema è cambiato.
    private func reloadChangedWindows() {
        var changed = false
        for w in windows {
            let t = theme(for: w.targetScreen)
            guard t.id != w.theme.id else { continue }
            // prima la qualità del tema nuovo, così la pagina nasce già alla risoluzione giusta
            w.setQuality(capped(QualityPolicy.decide(mode: model.qualityMode, backingScale: w.targetScreen.backingScaleFactor,
                                                     heavy: t.heavy).quality, for: w))
            w.load(t, settings: ThemeSettingsStore.values(for: t))
            changed = true
        }
        if changed { applyQuality() }       // i temi pesanti disegnano a risoluzione più bassa
    }

    // MARK: AppActions

    func selectTheme(_ chosen: ThemeInfo) {
        Haptics.tap()
        if let target = model.targetDisplay {
            themeByDisplay["\(target)"] = chosen.id == globalTheme.id ? nil : chosen.id
        } else {
            guard chosen.id != globalTheme.id || !themeByDisplay.isEmpty else { return }
            globalTheme = chosen
            themeByDisplay = [:]              // "Tutti": un solo tema ovunque
        }
        saveThemes()
        defaults.set(Date().timeIntervalSince1970, forKey: "lastRotation")
        showTheme(shownTheme())
        reloadChangedWindows()
        updateStatusIcon()
        updateDockIcon()
        if model.lockScreen { scheduleLockScreen(delay: 1) }
    }

    func setTargetDisplay(_ id: CGDirectDisplayID?) {
        Haptics.tick()
        model.targetDisplay = id
        showTheme(shownTheme())
    }

    func setThemeSetting(_ key: String, value: Double) {
        let t = model.theme
        if let p = t.params.first(where: { $0.key == key }) {
            let old = model.themeSettings[key] ?? p.def
            switch p.kind {
            case .toggle:
                Haptics.tap()
            case let .slider(lo, hi, step):
                let unit = step > 0 ? step : (hi - lo) / 10
                if value <= lo || value >= hi, old != value { Haptics.level() }
                else if (old / unit).rounded(.down) != (value / unit).rounded(.down) { Haptics.tick() }
            }
        }
        ThemeSettingsStore.set(value, key: key, for: t)
        model.themeSettings[key] = value
        pushSettings(for: t)
    }

    func resetThemeSettings() {
        Haptics.tap()
        let t = model.theme
        ThemeSettingsStore.reset(t)
        model.themeSettings = ThemeSettingsStore.values(for: t)
        pushSettings(for: t)
    }

    /// I cursori mandano molti valori al secondo: alla pagina arriva l'ultimo ogni ~80 ms.
    private func pushSettings(for t: ThemeInfo) {
        settingsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let values = ThemeSettingsStore.values(for: t)
            for w in self.windows where w.theme.id == t.id { w.setSettings(values) }
            if self.model.lockScreen { self.scheduleLockScreen(delay: 3) }
        }
        settingsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func newLandscape() {
        Haptics.tap()
        seed = Int.random(in: 1..<1_000_000)
        defaults.set(seed, forKey: "seed")
        windows.forEach { $0.setSeed(seed) }
        if model.lockScreen { scheduleLockScreen(delay: 1) }
    }

    func setPaused(_ paused: Bool) {
        Haptics.tap()
        manualPause = paused
        model.paused = paused
        poll()
    }

    func reloadTheme() { Haptics.tap(); windows.forEach { $0.reload() } }

    func setLockMode(_ mode: LockMode) {
        Haptics.level()
        let old = model.lockMode
        guard mode != old else { return }
        model.lockMode = mode
        defaults.set(mode.rawValue, forKey: "lockMode")
        switch mode {
        case .off:
            WallpaperExporter.shared.restoreOriginals()
        case .image:
            scheduleLockScreen(delay: 0)
        case .saver:
            scheduleLockScreen(delay: 0)
            installScreenSaver()            // va scelto in Impostazioni → Salvaschermo
        }
    }

    private func macLocked() {
        guard model.lockMode == .saver else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
        }
    }

    private func alert(_ title: String, _ text: String) {
        panel.close()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    func setShowInDock(_ on: Bool) {
        Haptics.tap()
        model.showInDock = on
        defaults.set(on, forKey: "showInDock")
        applyDockPolicy()
    }

    func setQualityMode(_ mode: QualityMode) {
        Haptics.level()
        model.qualityMode = mode
        defaults.set(mode.rawValue, forKey: "qualityMode")
        applyQuality()
    }

    func setLightMode(_ mode: LightMode) {
        Haptics.level()
        model.lightMode = mode
        defaults.set(mode.rawValue, forKey: "lightMode")
        applyLight()
    }

    func setRotation(_ mode: RotationMode) {
        Haptics.level()
        model.rotation = mode
        defaults.set(mode.rawValue, forKey: "rotation")
        defaults.set(Date().timeIntervalSince1970, forKey: "lastRotation")
    }

    func setRipples(_ on: Bool) {
        Haptics.tap()
        model.ripples = on
        defaults.set(on, forKey: "ripples")
        applyRipples()
    }

    /// Apre Lichen.saver: Impostazioni di Sistema chiede se installarlo per l'utente.
    func installScreenSaver() {
        Haptics.tap()
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Lichen.saver"),
                          ThemeCatalog.resources.deletingLastPathComponent().appendingPathComponent("dist/Lichen.app/Contents/Resources/Lichen.saver")]
        guard let saver = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            NSLog("[lichen] Lichen.saver non trovato")
            return
        }
        panel.close()
        if model.saverInstalled {
            openScreenSaverSettings()
            return
        }
        NSWorkspace.shared.open(saver)
        // installarlo non basta: va scelto in Impostazioni → Salvaschermo
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.model.refreshSaverInstalled()
            self?.openScreenSaverSettings()
        }
    }

    private func openScreenSaverSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
    }

    func startScreenSaver() {
        Haptics.tap()
        panel.close()
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Atmosfera: luce, rotazione, clic

    private func applyLight() {
        let tint = SunLight.currentTint(mode: model.lightMode)
        windows.forEach { $0.setLight(tint) }
    }

    private func rotateIfDue() {
        guard let interval = model.rotation.interval else { return }
        let last = defaults.double(forKey: "lastRotation")
        if Date().timeIntervalSince1970 - last >= interval { rotateTheme() }
    }

    /// Un tema diverso da quello attuale, su tutti gli schermi.
    private func rotateTheme() {
        let others = ThemeCatalog.all.filter { $0.id != globalTheme.id }
        guard let next = others.randomElement() else { return }
        globalTheme = next
        themeByDisplay = [:]
        saveThemes()
        defaults.set(Date().timeIntervalSince1970, forKey: "lastRotation")
        showTheme(shownTheme())
        if !windows.isEmpty {
            reloadChangedWindows()
            updateStatusIcon()
            updateDockIcon()
            if model.lockScreen { scheduleLockScreen(delay: 4) }
        }
    }

    /// I clic arrivano al Finder; Lichen li osserva soltanto (monitor globale, nessun permesso in più).
    private func applyRipples() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        guard model.ripples else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let p = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.desktopClicked(at: p) }
        }
    }

    private func desktopClicked(at p: NSPoint) {
        guard !manualPause, isDesktop(at: p) else { return }
        windows.forEach { $0.ripple(atScreenPoint: p) }
        poll()      // se era in pausa automatica riparte subito (e l'onda con lei)
    }

    private func setHidden(_ reason: String, _ on: Bool) {
        let changed = on ? hiddenReasons.insert(reason).inserted : hiddenReasons.remove(reason) != nil
        guard changed else { return }
        NSLog("[lichen] desktop %@: %@", on ? "nascosto" : "visibile", reason)
        if !on { applyLight() }
        poll()
    }

    /// Vero se sotto il puntatore non c'è nessuna finestra normale né un'icona del Finder.
    private func isDesktop(at p: NSPoint) -> Bool {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let q = CGPoint(x: p.x, y: primaryHeight - p.y)          // coordinate Quartz
        if lastIconRects.contains(where: { $0.contains(q) }) { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { continue }
            if rect.contains(q) { return false }
        }
        return true
    }

    // MARK: Dock e schermata di blocco

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(model.showInDock ? .regular : .accessory)
        updateDockIcon()
    }

    private func updateDockIcon() {
        guard model.showInDock else { return }
        NSApp.applicationIconImage = IconArt.dockIcon(for: globalTheme) ?? NSImage(named: NSImage.applicationIconName)
    }

    /// Lo sfondo di sistema (e quindi la schermata di blocco) segue il tema, senza icone.
    private func scheduleLockScreen(delay: TimeInterval) {
        lockScreenWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.lockScreen else { return }
            self.model.busy = "Aggiorno la schermata di blocco…"
            WallpaperExporter.shared.applyLockScreen(themeFor: { [unowned self] in self.theme(for: $0) },
                                                     seed: self.seed) { [weak self] in
                self?.model.busy = nil
            }
        }
        lockScreenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Qualità

    private func decision(for screen: NSScreen) -> QualityPolicy.Decision {
        if let id = screen.displayID, let d = decisions[id] { return d }
        return QualityPolicy.decide(mode: model.qualityMode, backingScale: screen.backingScaleFactor,
                                    heavy: theme(for: screen).heavy)
    }

    private func capped(_ q: RenderQuality, for w: DesktopWindow) -> RenderQuality {
        guard let id = w.displayID, let cap = fpsCaps[id] else { return q }
        return RenderQuality(scale: q.scale, fps: min(q.fps, cap))
    }

    private func effectiveQuality(for w: DesktopWindow) -> RenderQuality {
        capped(decision(for: w.targetScreen).quality, for: w)
    }

    /// Risoluzione e fps per ogni schermo; in automatico segue batteria, Risparmio energetico, temperatura.
    private func applyQuality() {
        lastQualityCheck = Date()
        var reason = ""
        decisions = [:]
        for w in windows {
            let d = QualityPolicy.decide(mode: model.qualityMode, backingScale: w.targetScreen.backingScaleFactor,
                                         heavy: w.theme.heavy)
            if let id = w.displayID { decisions[id] = d }
            let q = capped(d.quality, for: w)
            if q != w.themeView.quality { NSLog("[lichen] qualità %@ → %.2fx %d fps", d.reason, q.scale, q.fps) }
            w.setQuality(q)
            reason = d.reason
        }
        if model.qualityReason != reason { model.qualityReason = reason }
    }

    // MARK: Finestre

    /// Crea una finestra per ogni schermo nuovo, riusa (senza ricaricare) quelle degli schermi già noti.
    private func syncWindows() {
        var keep: [DesktopWindow] = []
        let tint = SunLight.currentTint(mode: model.lightMode)
        for screen in NSScreen.screens {
            if let w = windows.first(where: { $0.displayID == screen.displayID }) {
                w.move(to: screen)
                keep.append(w)
            } else {
                let t = theme(for: screen)
                let w = DesktopWindow(screen: screen, theme: t, seed: seed, quality: decision(for: screen).quality,
                                      settings: ThemeSettingsStore.values(for: t))
                w.setLight(tint, seconds: 0)
                w.orderFront(nil)
                keep.append(w)
            }
        }
        for w in windows where !keep.contains(where: { $0 === w }) { w.orderOut(nil) }
        windows = keep
        reloadChangedWindows()
        refreshScreens()
        applyQuality()
    }

    @objc private func screensChanged() {
        syncWindows()
        poll()
    }

    /// Le chiamate al Finder (Accessibility) e l'elenco finestre girano fuori dal thread principale.
    /// Ogni 0,4 s mentre il desktop si vede; quando tutto è in pausa basta un controllo ogni ~1,2 s
    /// e senza leggere le icone dal Finder (non si vedono comunque).
    private func scheduledPoll() {
        pollTick += 1
        if allPaused && pollTick % 3 != 0 { return }
        poll()
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        let screens = NSScreen.screens
        let readIcons = !allPaused || pollTick % 6 == 0
        let previous = lastIconRects
        axQueue.async { [weak self] in
            let trusted = AXIsProcessTrusted()
            let rects = trusted ? (readIcons ? IconReader.readIconRects() : previous) : []
            let visible = CoverDetector.visibleFraction(screens)
            let idle = Attention.idleSeconds
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                self.apply(trusted: trusted, rects: rects, visible: visible, idle: idle)
            }
        }
    }

    private func apply(trusted: Bool, rects: [CGRect], visible: [CGDirectDisplayID: Double], idle: TimeInterval) {
        if trusted != lastTrusted {
            lastTrusted = trusted
            model.trusted = trusted
            updateStatusIcon()
        }
        lastIconRects = rects
        if model.iconCount != rects.count { model.iconCount = rects.count }
        if Date().timeIntervalSince(lastQualityCheck) > 5 { applyQuality() }
        var anyAuto = false, everyPaused = !windows.isEmpty
        let hidden = !hiddenReasons.isEmpty
        for w in windows {
            if trusted { w.updateIcons(rects) }
            var isCovered = false
            if let id = w.displayID {
                let seen = visible[id] ?? 1
                let cap = Attention.fpsCap(visible: seen, idle: idle)
                if fpsCaps[id] != cap {
                    fpsCaps[id] = cap
                    w.setQuality(effectiveQuality(for: w))
                }
                if seen < Attention.hiddenBelow {
                    let since = coveredSince[id] ?? Date()
                    coveredSince[id] = since
                    isCovered = Date().timeIntervalSince(since) > 2
                } else {
                    coveredSince[id] = nil
                }
            }
            let systemPause = isCovered || decision(for: w.targetScreen).pause
            anyAuto = anyAuto || systemPause
            let pause = manualPause || systemPause || hidden
            if pause != w.paused { NSLog("[lichen] schermo %u %@", w.displayID ?? 0, pause ? "in pausa" : "riparte") }
            w.paused = pause
            everyPaused = everyPaused && pause
        }
        allPaused = everyPaused
        if model.autoPaused != anyAuto { model.autoPaused = anyAuto }
    }
}
