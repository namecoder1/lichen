import AppKit
import WebKit

/// Un tema è una pagina HTML/WebGL in Resources/themes che parla il protocollo host di Deskland:
///   pagina → host: "ready"
///   host → pagina: {t:"settings", v:{...}} · {t:"icons", vis:true, r:[[l,t,r,b], ...]} (pixel della pagina) · {t:"pause", v:bool}
/// File condiviso tra l'app e il salvaschermo (Lichen.saver).
struct ThemeInfo: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case classic = "Classici", nature = "Natura", style = "Stile"
    }
    let id: String
    let name: String
    let page: String       // percorso relativo a Resources/themes
    let category: Category
    let symbol: String     // SF Symbol
    let tagline: String
    let credit: String?

    /// Pagine che ridisegnano tutto lo schermo a ogni fotogramma con uno shader pesante (Deskland):
    /// l'host le fa disegnare a risoluzione e fps più bassi.
    var heavy: Bool { page.hasPrefix("deskland/") }

    /// Anteprima: Resources/thumbs/<id>.(jpg|png|webp)
    var thumbnail: NSImage? { ThemeCatalog.thumbnail(for: id) }
}

enum ThemeCatalog {
    static let all: [ThemeInfo] = [
        .init(id: "beach",     name: "Spiaggia",          page: "deskland/flat.html",     category: .classic, symbol: "beach.umbrella",
              tagline: "Coste turchesi, kayak e palme", credit: "Deskland"),
        .init(id: "meadow",    name: "Prato",             page: "deskland/meadow.html",   category: .classic, symbol: "cloud.sun",
              tagline: "Nuvole, un aquilone e un gattino", credit: "Deskland"),
        .init(id: "zen",       name: "Giardino zen",      page: "lichen/zen.html",        category: .classic, symbol: "leaf",
              tagline: "Muschio, rocce e ghiaia rastrellata", credit: nil),
        .init(id: "reef",      name: "Barriera corallina", page: "lichen/reef.html",      category: .nature,  symbol: "fish",
              tagline: "Coralli, caustiche e banchi di pesci", credit: nil),
        .init(id: "pixel",     name: "Pixel RPG",         page: "lichen/pixel.html",      category: .style,   symbol: "gamecontroller",
              tagline: "Una mappa a 16 bit", credit: nil),
        .init(id: "topo",      name: "Topografica",       page: "lichen/topo.html",       category: .style,   symbol: "map",
              tagline: "Curve di livello e tinte altimetriche", credit: nil),
        .init(id: "blueprint", name: "Blueprint",         page: "lichen/blueprint.html",  category: .style,   symbol: "ruler",
              tagline: "Carta da progetto e quote tecniche", credit: nil),
    ]

    static func byId(_ id: String?) -> ThemeInfo {
        all.first { $0.id == id } ?? all[0]
    }

    /// `demo`: la pagina gira senza host e mostra icone finte (anteprime e snapshot).
    static func url(for theme: ThemeInfo, demo: Bool = false) -> URL {
        URL(string: "\(ThemeSchemeHandler.scheme)://app/\(theme.page)\(demo ? "" : "?wallpaper=1")")!
    }

    /// Cartella delle risorse. Nell'app: Contents/Resources (o Resources/ del progetto in sviluppo).
    /// Il salvaschermo la imposta sul proprio bundle prima di usare il catalogo.
    static var resources: URL = defaultResources()

    private static func defaultResources() -> URL {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL, fm.fileExists(atPath: res.appendingPathComponent("themes").path) {
            return res
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources")
            if fm.fileExists(atPath: candidate.appendingPathComponent("themes").path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return Bundle.main.bundleURL
    }

    static var root: URL { resources.appendingPathComponent("themes") }

    private static var thumbCache: [String: NSImage] = [:]
    static func thumbnail(for id: String) -> NSImage? {
        if let img = thumbCache[id] { return img }
        for ext in ["jpg", "png", "webp"] {
            let url = resources.appendingPathComponent("thumbs/\(id).\(ext)")
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 720,
                      kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else { continue }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
            thumbCache[id] = img
            return img
        }
        return nil
    }
}

/// Serve i file dei temi da `lichen://app/...`. Con file:// WebKit considererebbe ogni file
/// un'origine diversa e WebGL rifiuterebbe le immagini (palme, gatto, bambino) come "cross-origin".
final class ThemeSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lichen"

    private static let mime: [String: String] = [
        "html": "text/html", "js": "text/javascript", "json": "application/json",
        "css": "text/css", "png": "image/png", "webp": "image/webp", "svg": "image/svg+xml",
        "jpg": "image/jpeg",
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let root = ThemeCatalog.root.standardizedFileURL
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        // Niente percorsi fuori dalla cartella dei temi.
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = Self.mime[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": type,
                                                      "Content-Length": "\(data.count)"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
