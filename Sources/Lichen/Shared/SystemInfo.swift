import AppKit
import IOKit.ps

/// Informazioni sul Mac usate per scegliere la qualità di disegno.
enum SystemInfo {
    /// true su Mac Intel (anche se l'app gira nativa x86_64); false su Apple Silicon, anche sotto Rosetta.
    static let isIntel: Bool = {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return !(sysctlbyname("hw.optional.arm64", &v, &size, nil, 0) == 0 && v == 1)
    }()

    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }

    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    static var thermal: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
}

/// Modalità di qualità scelta dall'utente.
enum QualityMode: String, CaseIterable, Identifiable {
    case auto, high, balanced, saver
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Automatica"
        case .high: "Massima"
        case .balanced: "Bilanciata"
        case .saver: "Risparmio"
        }
    }
}

/// Decide risoluzione, frame al secondo e pausa in base alla modalità e allo stato del Mac.
enum QualityPolicy {
    struct Decision: Equatable {
        var quality: RenderQuality
        var pause: Bool
        var reason: String
    }

    /// `heavy`: tema che ridisegna tutto lo schermo a ogni fotogramma (acqua, nuvole). A piena risoluzione
    /// Retina costa metà della GPU di un M3 Pro: si disegna a meno pixel (l'immagine è morbida e regge
    /// bene l'ingrandimento) e a meno fotogrammi. I pixel crescono col quadrato della scala.
    static func decide(mode: QualityMode, backingScale: CGFloat, heavy: Bool = false) -> Decision {
        let high = heavy ? RenderQuality(scale: min(backingScale, 1.25), fps: 30)
                         : RenderQuality(scale: backingScale, fps: 30)
        let balanced = heavy ? RenderQuality(scale: min(backingScale, 1), fps: 24)
                             : RenderQuality(scale: min(backingScale, SystemInfo.isIntel ? 1 : 1.5), fps: 30)
        let saver = heavy ? RenderQuality(scale: min(backingScale, 0.75), fps: 20)
                          : RenderQuality(scale: 1, fps: 20)
        switch mode {
        case .high: return .init(quality: high, pause: false, reason: "Massima")
        case .balanced: return .init(quality: balanced, pause: false, reason: "Bilanciata")
        case .saver: return .init(quality: saver, pause: false, reason: "Risparmio")
        case .auto: break
        }
        // Automatica: prima la salute del Mac, poi l'alimentazione, poi l'hardware.
        switch SystemInfo.thermal {
        case .critical: return .init(quality: saver, pause: true, reason: "In pausa: Mac molto caldo")
        case .serious: return .init(quality: saver, pause: false, reason: "Risparmio: Mac caldo")
        default: break
        }
        if SystemInfo.lowPowerMode { return .init(quality: saver, pause: false, reason: "Risparmio energetico") }
        if SystemInfo.onBattery {
            return SystemInfo.isIntel ? .init(quality: saver, pause: false, reason: "Risparmio: a batteria")
                                      : .init(quality: balanced, pause: false, reason: "Bilanciata: a batteria")
        }
        if SystemInfo.isIntel { return .init(quality: balanced, pause: false, reason: "Bilanciata: Mac Intel") }
        if heavy { return .init(quality: balanced, pause: false, reason: "Bilanciata: tema animato") }
        return .init(quality: high, pause: false, reason: "Massima")
    }
}
