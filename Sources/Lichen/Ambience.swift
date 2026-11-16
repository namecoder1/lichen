import AppKit

/// Luce dell'ora del giorno.
enum LightMode: String, CaseIterable, Identifiable {
    case off, sun, appearance
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return L("Always day")
        case .sun: return L("Follow the sun")
        case .appearance: return L("Follow dark mode")
        }
    }
}

/// Ogni quanto Lichen cambia tema da solo.
enum RotationMode: String, CaseIterable, Identifiable {
    case off, hourly, daily, launch
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return L("Never")
        case .hourly: return L("Every hour")
        case .daily: return L("Every day")
        case .launch: return L("At every launch")
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .hourly: return 3600
        case .daily: return 86400
        default: return nil
        }
    }
}

enum SunLight {
    /// Altezza del sole in gradi. Senza permesso di localizzazione: la longitudine si ricava dal fuso
    /// orario (al netto dell'ora legale), la latitudine è quella media europea.
    static func elevation(at date: Date = Date(), latitude: Double = 45) -> Double {
        let tz = TimeZone.current
        let standardOffset = Double(tz.secondsFromGMT(for: date)) - tz.daylightSavingTimeOffset(for: date)
        let longitude = standardOffset / 3600 * 15

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let utcHours = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600

        let g = 2 * Double.pi / 365 * (day - 1 + (utcHours - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
            + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let solarMinutes = utcHours * 60 + eqTime + 4 * longitude
        let hourAngle = (solarMinutes / 4 - 180) * Double.pi / 180
        let lat = latitude * Double.pi / 180
        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        return 90 - acos(max(-1, min(1, cosZenith))) * 180 / Double.pi
    }

    /// Dal giorno pieno (nessun velo) al tramonto dorato, all'ora blu, alla notte.
    static func tint(elevation e: Double) -> LightTint {
        // (altezza, colore, intensità) — interpolati linearmente
        let stops: [(Double, [Double], Double)] = [
            (-14, [0.24, 0.30, 0.56], 0.50),
            (-6, [0.42, 0.40, 0.68], 0.38),
            (-1, [0.86, 0.56, 0.62], 0.30),
            (4, [1.00, 0.70, 0.46], 0.24),
            (12, [1.00, 0.86, 0.70], 0.08),
            (20, [1.00, 1.00, 1.00], 0.00),
        ]
        if e <= stops[0].0 { return LightTint(rgb: stops[0].1, alpha: stops[0].2) }
        for i in 1..<stops.count where e <= stops[i].0 {
            let a = stops[i - 1], b = stops[i]
            let t = (e - a.0) / (b.0 - a.0)
            let rgb = zip(a.1, b.1).map { $0 + ($1 - $0) * t }
            return LightTint(rgb: rgb, alpha: a.2 + (b.2 - a.2) * t)
        }
        return .none
    }

    static func currentTint(mode: LightMode) -> LightTint {
        switch mode {
        case .off:
            return .none
        case .sun:
            let t = tint(elevation: elevation())
            // arrotondato: evita di rimandare il velo alla pagina per variazioni impercettibili
            return LightTint(rgb: t.rgb.map { ($0 * 100).rounded() / 100 }, alpha: (t.alpha * 100).rounded() / 100)
        case .appearance:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? LightTint(rgb: [0.34, 0.36, 0.62], alpha: 0.42) : .none
        }
    }
}
