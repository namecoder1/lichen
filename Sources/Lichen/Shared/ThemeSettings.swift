import Foundation

/// Un'impostazione regolabile di un tema. Arriva alla pagina con il messaggio
/// `{t:"settings", v:{chiave: valore}}` (per i temi di Deskland sono le chiavi dei loro cursori).
struct ThemeParam: Identifiable, Hashable {
    enum Kind: Hashable {
        case slider(min: Double, max: Double, step: Double)
        case toggle
    }
    let key: String
    let label: String
    let symbol: String
    let kind: Kind
    let def: Double
    var id: String { key }

    static func slider(_ key: String, _ label: String, _ symbol: String,
                       _ range: ClosedRange<Double>, def: Double, step: Double = 0) -> ThemeParam {
        ThemeParam(key: key, label: label, symbol: symbol,
                   kind: .slider(min: range.lowerBound, max: range.upperBound, step: step), def: def)
    }

    static func toggle(_ key: String, _ label: String, _ symbol: String, def: Bool = true) -> ThemeParam {
        ThemeParam(key: key, label: label, symbol: symbol, kind: .toggle, def: def ? 1 : 0)
    }
}

extension ThemeInfo {
    /// Cursori e interruttori del tema (i valori predefiniti coincidono con quelli delle pagine).
    var params: [ThemeParam] {
        switch id {
        case "beach":
            return [
                .slider("sigma", "Ampiezza delle isole", "circle.dashed", 40...200, def: 85, step: 1),
                .slider("shallow", "Acqua bassa", "water.waves", 120...700, def: 260, step: 1),
                .slider("palms", "Palme", "tree", 0...10, def: 4, step: 1),
                .slider("kayaks", "Kayak", "figure.water.fitness", 0...4, def: 2, step: 1),
                .slider("birds", "Gabbiani", "bird", 0...8, def: 3, step: 1),
            ]
        case "meadow":
            return [
                .slider("sigma", "Ampiezza dei prati", "circle.dashed", 40...200, def: 72, step: 1),
                .slider("cover", "Nuvole", "cloud", 0...1, def: 0.3),
                .slider("flow", "Vento", "wind", 0...3, def: 1),
                .toggle("showBoy", "Bambino con l'aquilone", "figure.run"),
                .toggle("showCat", "Gattino", "pawprint"),
            ]
        case "zen":
            return [
                .slider("sigma", "Ampiezza del muschio", "circle.dashed", 20...90, def: 40, step: 1),
                .slider("rings", "Anelli attorno alle isole", "circle.circle", 0...10, def: 5, step: 1),
                .slider("spacing", "Distanza tra i solchi", "line.3.horizontal", 9...26, def: 15, step: 1),
                .slider("leaves", "Foglie cadute", "leaf", 0...1.2, def: 1),
            ]
        case "reef":
            return [
                .slider("sigma", "Ampiezza dei banchi", "circle.dashed", 30...120, def: 60, step: 1),
                .slider("reef", "Fascia di coralli", "sparkles", 20...160, def: 80, step: 1),
                .slider("fish", "Banchi di pesci", "fish", 0...4, def: 4, step: 1),
            ]
        case "pixel":
            return [
                .slider("sigma", "Ampiezza delle isole", "circle.dashed", 30...100, def: 52, step: 1),
                .slider("trees", "Alberi", "tree", 0...0.8, def: 0.38),
                .toggle("clouds", "Ombre delle nuvole", "cloud"),
            ]
        case "topo":
            return [
                .slider("sigma", "Ampiezza dei rilievi", "circle.dashed", 40...140, def: 70, step: 1),
                .slider("interval", "Equidistanza delle curve", "line.3.horizontal", 6...24, def: 11, step: 1),
                .toggle("grid", "Reticolo", "grid"),
            ]
        case "blueprint":
            return [
                .slider("sigma", "Distanza delle quote", "circle.dashed", 14...60, def: 26, step: 1),
                .slider("parts", "Ingranaggi", "gearshape", 0...5, def: 5, step: 1),
                .toggle("grid", "Carta millimetrata", "grid"),
            ]
        default:
            return []
        }
    }
}

/// Valori scelti dall'utente, per tema: UserDefaults "settings.<id>" = [chiave: valore].
enum ThemeSettingsStore {
    static func values(for theme: ThemeInfo, in defaults: UserDefaults = .standard) -> [String: Double] {
        let saved = defaults.dictionary(forKey: "settings.\(theme.id)") as? [String: Double] ?? [:]
        var out: [String: Double] = [:]
        for p in theme.params { out[p.key] = saved[p.key] ?? p.def }
        return out
    }

    static func set(_ value: Double, key: String, for theme: ThemeInfo, in defaults: UserDefaults = .standard) {
        var saved = defaults.dictionary(forKey: "settings.\(theme.id)") as? [String: Double] ?? [:]
        saved[key] = value
        defaults.set(saved, forKey: "settings.\(theme.id)")
    }

    static func reset(_ theme: ThemeInfo, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "settings.\(theme.id)")
    }
}
