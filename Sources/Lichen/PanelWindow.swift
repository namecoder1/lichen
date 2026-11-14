import AppKit
import Combine
import SwiftUI

/// Pannello della barra dei menu: finestra senza bordi con angoli molto arrotondati
/// (al posto di NSPopover, che ha la freccia e un raggio fisso). Si chiude con un clic fuori o Esc.
@MainActor
final class PanelController {
    static let cornerRadius: CGFloat = 30

    private let panel: FloatingPanel
    private let model: AppModel
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var sizeSub: AnyCancellable?
    private weak var anchor: NSStatusBarButton?
    private var shrinkWork: DispatchWorkItem?
    private var lastPageChange = Date.distantPast
    private let hosting: NSHostingView<PanelView>
    private let container = NSView()
    /// Chiamato all'apertura (true) e alla chiusura (false) del pannello.
    var onVisibilityChange: ((Bool) -> Void)?

    var isShown: Bool { panel.isVisible }

    init(model: AppModel) {
        self.model = model
        panel = FloatingPanel()

        // La misura della finestra la decide solo PanelController (dalla misura del contenuto SwiftUI):
        // nessun vincolo automatico che "litighi" con setFrame e costringa a ricalcolare il layout.
        hosting = NSHostingView(rootView: PanelView(model: model))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(x: 0, y: 0, width: 364, height: 520)
        hosting.autoresizingMask = [.width, .minYMargin]      // agganciato in alto
        container.frame = hosting.frame
        container.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let backdrop: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = container
            backdrop = glass
        } else {
            let fx = NSVisualEffectView()
            fx.material = .popover
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.maskImage = Self.roundedMask(radius: Self.cornerRadius)
            container.frame = fx.bounds
            fx.addSubview(container)
            backdrop = fx
        }
        // Contenitore ritagliato agli angoli: fuori dal raggio la finestra è davvero trasparente,
        // così anche l'ombra di sistema (calcolata dall'alfa) segue la forma arrotondata.
        let clip = NSView(frame: hosting.frame)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Self.cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        backdrop.frame = clip.bounds
        backdrop.autoresizingMask = [.width, .height]
        clip.addSubview(backdrop)
        panel.contentView = clip
        panel.setContentSize(hosting.frame.size)
        // costruisce subito le viste (pagine, controlli AppKit) e fa un primo disegno invisibile
        // (vetro, livelli, shader): la prima apertura vera non scatta
        hosting.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in self?.prewarm() }

        // Niente animazioni della finestra (bloccano il thread principale). Se il contenuto cresce la
        // finestra si allunga subito; se si accorcia durante un cambio pagina aspetta la fine della transizione.
        sizeSub = model.panelSizeChanged
            .removeDuplicates()
            .sink { [weak self] size in
                guard let self, size.width > 10, size.height > 10 else { return }
                self.shrinkWork?.cancel()
                let midTransition = Date().timeIntervalSince(self.lastPageChange) < 0.35
                if !self.panel.isVisible || size.height >= self.panel.frame.height || !midTransition {
                    self.layout(size: size)
                } else {
                    self.pinContent(height: size.height)
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.layout(size: self.model.panelSize)
                    }
                    self.shrinkWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
                }
            }
        // @Published notifica prima del cambio: la nuova misura si calcola al giro successivo
        pageSub = model.$page.dropFirst().sink { [weak self] _ in
            self?.lastPageChange = Date()
            DispatchQueue.main.async { self?.model.updatePanelSize() }
        }
    }

    private var pageSub: AnyCancellable?

    private func prewarm() {
        guard !panel.isVisible else { return }
        model.prewarming = true
        hosting.layoutSubtreeIfNeeded()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.display()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.model.prewarming = false
            guard self.panel.alphaValue == 0, self.outsideMonitor == nil else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        }
    }

    func toggle(from button: NSStatusBarButton) {
        isShown ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        anchor = button
        model.page = .main
        // prima apertura: si misura il contenuto adesso
        if model.panelSize.height < 10 { hosting.layoutSubtreeIfNeeded() }
        var size = model.panelSize
        if size.height < 10 { size = hosting.fittingSize }
        if size.width < 10 || size.height < 10 { size = CGSize(width: 364, height: 520) }
        layout(size: size)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.display()
        panel.invalidateShadow()
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        installMonitors()
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        removeMonitors()
        onVisibilityChange?(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    /// Bordo superiore fisso sotto l'icona nella barra dei menu; cresce verso il basso.
    private func layout(size: CGSize) {
        guard let button = anchor ?? nil, let bw = button.window else {
            panel.setContentSize(size)
            pinContent(height: size.height)
            return
        }
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = b.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = b.minY - 6
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        pinContent(height: size.height)
        panel.invalidateShadow()
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
    }

    /// Il contenuto SwiftUI è alto esattamente quanto misurato e resta agganciato al bordo superiore.
    private func pinContent(height: CGFloat) {
        let bounds = panel.contentView?.bounds ?? container.bounds
        let f = NSRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        if hosting.frame != f { hosting.frame = f }
    }

    private func installMonitors() {
        removeMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }        // Esc
            MainActor.assumeIsolated {
                if self?.model.page == .settings { withAnimation(.snappy) { self?.model.page = .main } } else { self?.close() }
            }
            return nil
        }
    }

    private func removeMonitors() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
        keyMonitor = nil
    }

    /// Maschera a 9 fette per NSVisualEffectView (macOS < 26).
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }
}

final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 356, height: 480),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
