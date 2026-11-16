import Foundation

/// Testi dell'interfaccia. La chiave è il testo inglese (lingua di base); le traduzioni stanno in
/// Resources/<lingua>.lproj/Localizable.strings e macOS sceglie la lingua del sistema.
/// File condiviso con il salvaschermo, che imposta `bundle` sul proprio bundle.
enum L10n {
    static var bundle: Bundle = .main
}

/// Testo tradotto: `L("Paused")`.
func L(_ en: String) -> String {
    L10n.bundle.localizedString(forKey: en, value: en, table: nil)
}

/// Testo tradotto con argomenti in stile printf: `L("%d icons", n)`.
func L(_ en: String, _ args: CVarArg...) -> String {
    String(format: L(en), arguments: args)
}
