import AppKit
import SwiftUI

/// The app's windows: main (setup assistant / dashboard), Settings, About and Software Update.
/// Every window keeps living when closed, so closing simply hides it and the app keeps running.
@MainActor
enum AppWindows {
    private static var mainWindow: NSWindow?
    private static var settingsWindow: NSWindow?
    private static var aboutWindow: NSWindow?
    private static var updateWindow: NSWindow?

    private static func makeWindow<Content: View>(title: String, size: NSSize, minSize: NSSize? = nil,
                                                  resizable: Bool, autosave: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { mask.insert(.resizable) }
        window.styleMask = mask
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        if let minSize = minSize { window.minSize = minSize }
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }

    static func showMain() {
        if mainWindow == nil {
            mainWindow = makeWindow(title: AppInfo.name, size: NSSize(width: 700, height: 580),
                                    minSize: NSSize(width: 640, height: 480), resizable: true,
                                    autosave: "CRSubtitleReaderMainWindow",
                                    content: ContentView().environmentObject(AppState.shared))
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    static func closeMain() {
        mainWindow?.close()
    }

    static var isMainVisible: Bool { mainWindow?.isVisible ?? false }

    static func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "\(AppInfo.name) Settings", size: NSSize(width: 600, height: 520),
                                        resizable: false, autosave: "CRSubtitleReaderSettings",
                                        content: SettingsView().environmentObject(AppState.shared))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    static func openAbout() {
        if aboutWindow == nil {
            aboutWindow = makeWindow(title: "About \(AppInfo.name)", size: NSSize(width: 520, height: 560),
                                     resizable: false, autosave: "CRSubtitleReaderAbout", content: AboutView())
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    static func openUpdate() {
        if updateWindow == nil {
            updateWindow = makeWindow(title: "Software Update", size: NSSize(width: 560, height: 480),
                                      minSize: NSSize(width: 480, height: 360), resizable: true,
                                      autosave: "CRSubtitleReaderUpdate",
                                      content: UpdateView().environmentObject(AppState.shared))
        }
        NSApp.activate(ignoringOtherApps: true)
        updateWindow?.makeKeyAndOrderFront(nil)
    }

    static func closeUpdate() {
        updateWindow?.close()
    }
}
