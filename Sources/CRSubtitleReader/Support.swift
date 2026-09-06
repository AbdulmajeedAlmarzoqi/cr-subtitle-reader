import Foundation
import AppKit
import ServiceManagement

/// Posts VoiceOver announcements from the app itself (status changes, wizard steps).
enum Accessibility {
    @MainActor
    static func announce(_ text: String, priority: NSAccessibilityPriorityLevel = .high) {
        let element: Any = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: priority.rawValue,
        ])
    }
}

/// "Launch at login" through SMAppService (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Moves the app to /Applications when it runs from Downloads, a disk image or, worst of all,
/// App Translocation: a quarantined app launched straight from where it was unzipped runs from a
/// random read-only path every time, so macOS forgets its permissions on every launch and the
/// updater cannot replace it. Moving it with Finder is what ends translocation; the app does the
/// equivalent itself: copy to Applications, drop the quarantine flag, relaunch.
enum Relocator {
    static var isInApplications: Bool {
        let path = Bundle.main.bundleURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix("\(home)/Applications/")
    }

    /// True when Gatekeeper is running the app from a randomized AppTranslocation path.
    static var isTranslocated: Bool {
        Bundle.main.bundleURL.path.contains("/AppTranslocation/")
    }

    static var shouldOffer: Bool {
        !isInApplications && !UserDefaults.standard.bool(forKey: PrefKey.declinedMoveToApplications)
    }

    /// Copies the bundle to /Applications (or ~/Applications), removes the quarantine flag from the
    /// copy so it will not be translocated, and relaunches from there.
    @MainActor
    static func moveToApplications() throws {
        let fm = FileManager.default
        var target = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if !fm.isWritableFile(atPath: target.path) {
            target = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        }
        let destination = target.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            var trashed: NSURL?
            if (try? fm.trashItem(at: destination, resultingItemURL: &trashed)) == nil {
                try fm.removeItem(at: destination)
            }
        }
        try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? xattr.run()
        xattr.waitUntilExit()
        Log.info("Moved to \(destination.path)")
        UpdateInstaller.relaunch(at: destination)
    }
}

/// Finds Safari web apps ("Add to Dock") that point at Crunchyroll. Such an app is a separate
/// process with its own extension settings; it cannot be scripted, so only in-page reading works there.
enum WebAppDetector {
    struct WebApp {
        let name: String
        let url: URL
    }

    static func crunchyrollWebApps() -> [WebApp] {
        let fm = FileManager.default
        let folders = [
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
        ]
        var found: [WebApp] = []
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "app" {
                guard let bundle = Bundle(url: item),
                      let identifier = bundle.bundleIdentifier,
                      identifier.hasPrefix("com.apple.Safari.WebApp.") else { continue }
                let plist = item.appendingPathComponent("Contents/Info.plist")
                let text = (try? String(contentsOf: plist, encoding: .utf8)) ?? ""
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? item.deletingPathExtension().lastPathComponent
                let manifest = item.appendingPathComponent("Contents/Resources/manifest.json")
                let manifestText = (try? String(contentsOf: manifest, encoding: .utf8)) ?? ""
                if text.lowercased().contains("crunchyroll") || manifestText.lowercased().contains("crunchyroll") || name.lowercased().contains("crunchyroll") {
                    found.append(WebApp(name: name, url: item))
                }
            }
        }
        return found
    }
}

extension Date {
    var shortDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
