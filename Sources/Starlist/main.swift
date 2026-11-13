import AppKit
import StarlistKit

// The process starts on the main thread; say so, so the app's main-actor types can be used.
MainActor.assumeIsolated {
    // `--data-dir <path>` keeps the list, settings, and archives inside one folder.
    // Handy for trying things out without touching your real list.
    var paths = AppPaths.standard
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--data-dir"), flag + 1 < arguments.count {
        paths = .contained(in: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
    }

    let app = NSApplication.shared
    let delegate = AppDelegate(paths: paths)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
