import AppKit
import Combine
import ServiceManagement

/// Azioni che il pannello chiede all'app.
@MainActor
protocol AppActions: AnyObject {
    func selectTheme(_ theme: ThemeInfo)
    func newLandscape()
    func setPaused(_ paused: Bool)
    func reloadTheme()
    func setLockMode(_ mode: LockMode)
    func setShowInDock(_ on: Bool)
    func setQualityMode(_ mode: QualityMode)
    func installScreenSaver()
    func startScreenSaver()
    func openAccessibilitySettings()
    func setThemeSetting(_ key: String, value: Double)
    func resetThemeSettings()
    func setTargetDisplay(_ id: CGDirectDisplayID?)
    func setLightMode(_ mode: LightMode)
    func setRotation(_ mode: RotationMode)
    func setRipples(_ on: Bool)
    func checkForUpdates()
    func closePanel()
}

/// Uno schermo scelto nel pannello (con più monitor ognuno può avere il suo tema).
struct ScreenChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}

enum PanelPage { case main, settings }

/// Cosa mostra la schermata di blocco.
enum LockMode: String, CaseIterable, Identifiable {
    case off, image, saver
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Disattivata"
        case .image: return "Immagine del tema"
        case .saver: return "Salvaschermo al blocco"
        }
    }
    var short: String {
        switch self {
        case .off: return "Disattivato"
        case .image: return "Immagine"
        case .saver: return "Salvaschermo"
        }
    }
}

/// Stato osservato dal pannello.
@MainActor
final class AppModel: ObservableObject {
    @Published var theme: ThemeInfo
    @Published var paused = false
    @Published var trusted = true
    @Published var iconCount = 0
    @Published var lockMode: LockMode
    var lockScreen: Bool { lockMode != .off }
    @Published var showInDock: Bool
    @Published var launchAtLogin: Bool
    @Published var qualityMode: QualityMode
    @Published var qualityReason = ""
    @Published var autoPaused = false        // pausa decisa dal sistema (schermo coperto, Mac caldo)
    @Published var saverInstalled = false
    @Published var busy: String?
    @Published var page: PanelPage = .main
    /// All'avvio, in una finestra invisibile, si disegnano entrambe le pagine una volta (vedi PanelController).
    @Published var prewarming = false
    @Published var themeSettings: [String: Double] = [:]
    @Published var screens: [ScreenChoice] = []
    @Published var targetDisplay: CGDirectDisplayID?       // nil = tutti gli schermi
    @Published var lightMode: LightMode
    @Published var rotation: RotationMode
    @Published var ripples: Bool
    @Published var canCheckForUpdates = false
    /// Misura del pannello (pagina visibile + margini). Non @Published: cambiarla non deve ridisegnarlo.
    var panelSize: CGSize = .zero
    let panelSizeChanged = PassthroughSubject<CGSize, Never>()
    private var pageHeights: [PanelPage: CGFloat] = [:]

    func setPageHeight(_ h: CGFloat, for page: PanelPage) {
        pageHeights[page] = h
        updatePanelSize()
    }

    /// Da chiamare anche quando cambia pagina.
    func updatePanelSize() {
        guard let h = pageHeights[page], h > 0 else { return }
        let size = CGSize(width: 364, height: (h + 32).rounded(.up))
        if size != panelSize { panelSize = size; panelSizeChanged.send(size) }
    }

    weak var actions: AppActions?

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    init(theme: ThemeInfo) {
        self.theme = theme
        let d = UserDefaults.standard
        let savedLock = d.string(forKey: "lockMode") ?? ""
        lockMode = savedLock == "video" ? .image : LockMode(rawValue: savedLock)
            ?? (d.bool(forKey: "lockScreen") ? (d.bool(forKey: "lockAnimated") ? .saver : .image) : .off)
        showInDock = d.bool(forKey: "showInDock")
        qualityMode = QualityMode(rawValue: d.string(forKey: "qualityMode") ?? "") ?? .auto
        launchAtLogin = SMAppService.mainApp.status == .enabled
        d.register(defaults: ["lightMode": LightMode.sun.rawValue, "ripples": true])
        lightMode = LightMode(rawValue: d.string(forKey: "lightMode") ?? "") ?? .sun
        rotation = RotationMode(rawValue: d.string(forKey: "rotation") ?? "") ?? .off
        ripples = d.bool(forKey: "ripples")
        themeSettings = ThemeSettingsStore.values(for: theme)
        refreshSaverInstalled()
    }

    func refreshSaverInstalled() {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        saverInstalled = FileManager.default.fileExists(atPath: lib.appendingPathComponent("Screen Savers/Lichen.saver").path)
    }

    func toggleLaunchAtLogin(_ on: Bool) {
        Haptics.tap()
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[lichen] avvio al login: %@", error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
