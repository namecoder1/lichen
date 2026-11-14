import AppKit

// Punto d'ingresso: app normale oppure uno strumento di sviluppo (vedi DevTools.swift).

let args = CommandLine.arguments
if args.contains("--dump") {
    IconReader.dumpTree()
    exit(0)
}
if args.contains("--attention") {
    // quota di desktop visibile per schermo e secondi senza input (vedi Attention)
    for s in NSScreen.screens {
        let v = CoverDetector.visibleFraction([s])[s.displayID ?? 0] ?? 1
        print(String(format: "schermo %u: visibile %.0f%%", s.displayID ?? 0, v * 100))
    }
    print(String(format: "inattivo da %.0f s", Attention.idleSeconds))
    exit(0)
}
if let i = args.firstIndex(of: "--make-icon"), i + 1 < args.count {
    do { try IconArt.writeIconset(to: URL(fileURLWithPath: args[i + 1])); exit(0) } catch { print(error); exit(1) }
}

let app = NSApplication.shared
let delegate: NSApplicationDelegate
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let rest = Array(args[(i + 2)...])
    delegate = SnapshotDelegate(dir: URL(fileURLWithPath: args[i + 1]), ids: rest.filter { $0 != "--demo" },
                                demo: rest.contains("--demo"))
} else if let i = args.firstIndex(of: "--thumbs"), i + 1 < args.count {
    delegate = SnapshotDelegate(dir: URL(fileURLWithPath: args[i + 1]), ids: Array(args[(i + 2)...]),
                                demo: true, thumbs: true)
} else if args.contains("--panel-test") {
    delegate = MainActor.assumeIsolated { PanelTestDelegate() }
} else {
    delegate = MainActor.assumeIsolated { AppDelegate() }
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
