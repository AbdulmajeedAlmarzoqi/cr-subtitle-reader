import SwiftUI
import AppKit

@main
struct CRSubtitleReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup(AppInfo.name, id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 640, minHeight: 520)
                // Route crsr:// links to the existing window instead of opening a new one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in URLCommands.handle(url, state: state) }
        }
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppInfo.name)") { AppWindows.openAbout() }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await state.updates.check(userInitiated: true) }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("\(AppInfo.name) on GitHub") { NSWorkspace.shared.open(AppInfo.repositoryURL) }
                Button("Report a Problem…") { NSWorkspace.shared.open(AppInfo.issuesURL) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }

        MenuBarExtra(AppInfo.name, systemImage: "captions.bubble") {
            MenuBarContent()
                .environmentObject(state)
        }
    }
}

/// AppKit-level windows that SwiftUI scenes do not model well (About, Update).
@MainActor
enum AppWindows {
    private static var aboutWindow: NSWindow?
    private static var updateWindow: NSWindow?

    static func openAbout() {
        if aboutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.title = "About \(AppInfo.name)"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 560))
            window.center()
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    static func openUpdate(state: AppState) {
        if updateWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: UpdateView().environmentObject(state)))
            window.title = "Software Update"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 480))
            window.center()
            updateWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        updateWindow?.makeKeyAndOrderFront(nil)
    }

    static func closeUpdate() {
        updateWindow?.close()
    }

    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == AppInfo.name {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updateObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState.shared
        Log.info("Launched \(AppInfo.name) \(AppInfo.version) from \(Bundle.main.bundleURL.path); bridge loaded: \(state.bridge.isLoaded)")

        // Show the update window whenever the manager asks for it.
        updateObserver = state.updates.$showUpdateWindow.sink { show in
            Task { @MainActor in
                if show { AppWindows.openUpdate(state: state) } else { AppWindows.closeUpdate() }
            }
        }

        if state.setupCompleted {
            if Relocator.shouldOffer && !LaunchOptions.skipRelocation { offerMoveToApplications() }
            if UserDefaults.standard.bool(forKey: PrefKey.startReadingOnLaunch) {
                state.reader.start(announce: false)
            }
        }
        state.updates.startAutomaticChecks()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Log.info("AppDelegate received \(urls.count) URL(s)")
        for url in urls {
            URLCommands.handle(url, state: AppState.shared)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppWindows.showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.reader.stop(announce: false)
    }

    private func offerMoveToApplications() {
        let alert = NSAlert()
        alert.messageText = "Move \(AppInfo.name) to the Applications folder?"
        alert.informativeText = "Running from the Applications folder keeps automatic updates and Launch at Login working reliably."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            do {
                try Relocator.moveToApplications()
            } catch {
                let failure = NSAlert(error: error)
                failure.runModal()
            }
        } else {
            UserDefaults.standard.set(true, forKey: PrefKey.declinedMoveToApplications)
        }
    }
}
