import AppKit
import ApplicationServices

/// Legge le posizioni delle icone del desktop tramite l'Accessibility API del Finder.
/// Gerarchia tipica: Finder (app) → AXScrollArea "desktop" → AXGroup → AXImage (una per icona).
/// Le finestre del Finder (AXWindow) e la barra dei menu vengono saltate.
///
/// Le coordinate restituite sono quelle AX: punti, origine in alto a sinistra dello schermo principale.
enum IconReader {
    static func finderElement() -> AXUIElement? {
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return nil }
        let el = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.5)
        return el
    }

    /// Rettangoli icona + etichetta, in coordinate AX globali.
    static func readIconRects() -> [CGRect] {
        guard let finder = finderElement() else { return [] }
        var rects: [CGRect] = []
        walk(finder, depth: 0) { el, role in
            guard role == kAXImageRole,
                  let pos = point(el), let size = size(el), size.width > 0
            else { return }
            // AX dà solo l'immagine: allarghiamo per includere il nome sotto l'icona.
            rects.append(CGRect(x: pos.x - 18, y: pos.y - 2,
                                width: size.width + 36, height: size.height + 34))
        }
        return rects
    }

    /// Stampa l'albero AX del Finder (escluse le finestre): utile per il debug con `--dump`.
    static func dumpTree() {
        guard let finder = finderElement() else { print("Finder non trovato"); return }
        walk(finder, depth: 0) { el, role in
            let title: String = attr(el, kAXTitleAttribute) ?? ""
            let desc: String = attr(el, kAXRoleDescriptionAttribute) ?? ""
            let p = point(el).map { "(\(Int($0.x)),\(Int($0.y)))" } ?? ""
            let s = size(el).map { "\(Int($0.width))x\(Int($0.height))" } ?? ""
            print("\(role) [\(desc)] \"\(title)\" \(p) \(s)")
        }
    }

    // MARK: - Helper AX

    private static func walk(_ el: AXUIElement, depth: Int,
                             _ visit: (AXUIElement, String) -> Void) {
        guard depth <= 6 else { return }
        let role: String = attr(el, kAXRoleAttribute) ?? ""
        if role == kAXWindowRole || role == kAXMenuBarRole { return }
        visit(el, role)
        let children: [AXUIElement] = attr(el, kAXChildrenAttribute) ?? []
        for child in children { walk(child, depth: depth + 1, visit) }
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func axValue(_ el: AXUIElement, _ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID()
        else { return nil }
        return (v as! AXValue)
    }

    private static func point(_ el: AXUIElement) -> CGPoint? {
        guard let v = axValue(el, kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    private static func size(_ el: AXUIElement) -> CGSize? {
        guard let v = axValue(el, kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }
}
