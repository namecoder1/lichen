import AppKit

/// Feedback aptico del trackpad (Force Touch) per le azioni del pannello.
/// Sui Mac senza trackpad Force Touch non succede nulla.
enum Haptics {
    /// Azione confermata: scelta di un tema, interruttore, pulsante.
    static func tap() { perform(.generic) }
    /// Scatto: ogni passo di un cursore, cambio di pagina.
    static func tick() { perform(.alignment) }
    /// Cambio di livello: valore minimo/massimo, opzione di un menu.
    static func level() { perform(.levelChange) }

    private static func perform(_ p: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    }
}
