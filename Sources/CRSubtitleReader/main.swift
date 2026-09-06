import AppKit

// AppKit lifecycle: it gives full control over windows (closing keeps the app running, later
// launches open nothing), the main menu, the status item, reopen and crsr:// URL events.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
