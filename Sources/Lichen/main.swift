import AppKit

// Punto d'ingresso: app normale oppure uno strumento di sviluppo (vedi DevTools.swift).

let args = CommandLine.arguments
if args.contains("--dump") {
    IconReader.dumpTree()
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
