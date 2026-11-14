import AppKit

/// Disegno delle icone: icona dell'app (generata via codice con lo stesso "campo" dei temi)
/// e icona del Dock che riprende il tema attivo.
enum IconArt {
    // Griglia delle icone macOS: corpo 824/1024 centrato, angoli continui ~22.5%.
    private static func squircle(in rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.height * 0.225, transform: nil)
    }

    private static func bodyRect(_ size: CGFloat) -> CGRect {
        let inset = size * 100 / 1024
        return CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    }

    // MARK: Icona dell'app

    /// I "file" sull'isola (coordinate su 1024, origine in alto a sinistra).
    private static let files: [(CGRect, Bool)] = [
        (CGRect(x: 372, y: 352, width: 116, height: 140), false),
        (CGRect(x: 536, y: 360, width: 124, height: 132), true),    // cartella
        (CGRect(x: 454, y: 528, width: 116, height: 140), false),
    ]

    static func appIcon(size px: Int) -> CGImage? {
        let size = CGFloat(px)
        let k = size / 1024
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let body = bodyRect(size)

        // ombra dell'icona
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(squircle(in: body))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        // paesaggio calcolato pixel per pixel (mare, schiuma, sabbia, erba)
        let landscape = landscapeImage(px: px)
        ctx.saveGState()
        ctx.addPath(squircle(in: body))
        ctx.clip()
        if let landscape { ctx.draw(landscape, in: CGRect(x: 0, y: 0, width: size, height: size)) }

        // file e cartella sull'isola
        for (r, folder) in files {
            let rect = CGRect(x: r.minX * k, y: size - r.maxY * k, width: r.width * k, height: r.height * k)
            drawFile(ctx, rect, folder: folder, k: k)
        }

        // vetro: riflesso in alto e bordo luminoso
        let gloss = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(gray: 1, alpha: 0.32), CGColor(gray: 1, alpha: 0.0)] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 40 * k),
                               options: [])
        ctx.restoreGState()
        ctx.addPath(squircle(in: body.insetBy(dx: 1.5 * k, dy: 1.5 * k)))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
        ctx.setLineWidth(3 * k)
        ctx.strokePath()
        return ctx.makeImage()
    }

    private static func landscapeImage(px: Int) -> CGImage? {
        let k = Float(px) / 1024
        var data = [UInt32](repeating: 0, count: px * px)
        let sigma: Float = 84, is2 = 1 / (sigma * sigma)
        let rects = files.map { (r, _) in
            (cx: Float(r.midX) * k, cy: Float(r.midY) * k, hw: Float(r.width) * 0.25 * k, hh: Float(r.height) * 0.25 * k)
        }
        func rgb(_ r: Float, _ g: Float, _ b: Float) -> UInt32 {
            let c = { (v: Float) in UInt32(max(0, min(255, v * 255))) }
            return 0xFF00_0000 | (c(b) << 16) | (c(g) << 8) | c(r)
        }
        func mix(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
            let t = max(0, min(1, t))
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
        let deep: (Float, Float, Float) = (0.07, 0.36, 0.62), shallow: (Float, Float, Float) = (0.26, 0.76, 0.80)
        let foam: (Float, Float, Float) = (0.93, 0.98, 0.98), sand: (Float, Float, Float) = (0.96, 0.87, 0.64)
        let grass: (Float, Float, Float) = (0.46, 0.76, 0.38), grassD: (Float, Float, Float) = (0.32, 0.62, 0.30)

        for y in 0..<px {
            for x in 0..<px {
                let fx = Float(x) + 0.5, fy = Float(y) + 0.5
                // leggera deformazione per una costa organica
                let wx = fx + sin(fy * 0.031 / k) * 10 * k, wy = fy + sin(fx * 0.027 / k) * 10 * k
                var f: Float = 0
                for r in rects {
                    let dx = max(abs(wx - r.cx) - r.hw, 0) / k, dy = max(abs(wy - r.cy) - r.hh, 0) / k
                    f += exp(-(dx * dx + dy * dy) * is2)
                }
                let g = log(max(f, 1e-13))
                let s = sigma * (sqrt(max(-g, 0)) - 1.0) - sigma * 0.6 * max(g, 0)
                var c: (Float, Float, Float)
                if s > 16 {
                    c = mix(shallow, deep, (s - 16) / 260)
                    // onde concentriche attorno all'isola
                    let wave = abs(sin(s * 0.11))
                    if s < 150 && wave < 0.12 { c = mix(c, foam, 0.35 * (1 - s / 150)) }
                } else if s > 6 { c = foam }
                else if s > -14 { c = sand }
                else { c = mix(grass, grassD, min(1, -(s + 14) / 60)) }
                // il bitmap ha la riga 0 in basso: capovolgiamo y
                data[(px - 1 - y) * px + x] = rgb(c.0, c.1, c.2)
            }
        }
        return data.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    private static func drawFile(_ ctx: CGContext, _ r: CGRect, folder: Bool, k: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * k), blur: 12 * k, color: CGColor(gray: 0, alpha: 0.28))
        if folder {
            let body = CGRect(x: r.minX, y: r.minY + 8 * k, width: r.width, height: r.height * 0.72)
            let tab = CGRect(x: r.minX + 6 * k, y: body.maxY - 14 * k, width: r.width * 0.42, height: 32 * k)
            ctx.setFillColor(CGColor(red: 0.22, green: 0.52, blue: 0.88, alpha: 1))
            ctx.addPath(CGPath(roundedRect: tab, cornerWidth: 8 * k, cornerHeight: 8 * k, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(CGColor(red: 0.40, green: 0.72, blue: 1.0, alpha: 1))
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil))
            ctx.fillPath()
        } else {
            let fold = 34 * k
            let path = CGMutablePath()
            path.move(to: CGPoint(x: r.minX + 10 * k, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX - 10 * k, y: r.minY))
            path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 10 * k), control: CGPoint(x: r.maxX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
            path.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX + 10 * k, y: r.maxY))
            path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 10 * k), control: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + 10 * k))
            path.addQuadCurve(to: CGPoint(x: r.minX + 10 * k, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
            ctx.setFillColor(CGColor(gray: 0.99, alpha: 1))
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            // angolo piegato
            let corner = CGMutablePath()
            corner.move(to: CGPoint(x: r.maxX - fold, y: r.maxY))
            corner.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY - fold + 6 * k))
            corner.addQuadCurve(to: CGPoint(x: r.maxX - fold + 6 * k, y: r.maxY - fold),
                                control: CGPoint(x: r.maxX - fold, y: r.maxY - fold))
            corner.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
            corner.closeSubpath()
            ctx.setFillColor(CGColor(gray: 0.86, alpha: 1))
            ctx.addPath(corner)
            ctx.fillPath()
            // righe di testo
            ctx.setFillColor(CGColor(red: 0.72, green: 0.78, blue: 0.85, alpha: 1))
            for i in 0..<4 {
                let w = (i == 3 ? 0.45 : 0.7) * r.width
                ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + 18 * k, y: r.minY + (26 + CGFloat(i) * 22) * k,
                                                       width: w - 18 * k, height: 8 * k),
                                   cornerWidth: 4 * k, cornerHeight: 4 * k, transform: nil))
            }
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// Scrive un .iconset completo (poi `iconutil -c icns`).
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                guard let img = appIcon(size: px) else { continue }
                let rep = NSBitmapImageRep(cgImage: img)
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }

    // MARK: Icona del Dock in tema

    /// L'anteprima del tema dentro la forma delle icone macOS, con il riflesso "vetro".
    static func dockIcon(for theme: ThemeInfo) -> NSImage? {
        guard let thumb = theme.thumbnail,
              let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let px = 512, size = CGFloat(px), k = size / 1024
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let body = bodyRect(size)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(squircle(in: body)); ctx.setFillColor(CGColor(gray: 0.2, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(squircle(in: body)); ctx.clip()
        // riempimento "aspect fill" centrato sulla zona destra dell'anteprima, dove stanno le icone
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let scale = max(body.width / iw, body.height / ih) * 1.25
        let dw = iw * scale, dh = ih * scale
        ctx.draw(cg, in: CGRect(x: body.maxX - dw * 0.92, y: body.midY - dh / 2, width: dw, height: dh))
        let gloss = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(gray: 1, alpha: 0.30), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 40 * k), options: [])
        ctx.restoreGState()
        ctx.addPath(squircle(in: body.insetBy(dx: 1.5 * k, dy: 1.5 * k)))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.45)); ctx.setLineWidth(3 * k); ctx.strokePath()
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: 512, height: 512))
    }
}
