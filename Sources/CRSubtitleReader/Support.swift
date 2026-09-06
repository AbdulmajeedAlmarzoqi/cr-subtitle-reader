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

/// Offers to move the app to /Applications when it runs from Downloads or a disk image.
enum Relocator {
    static var isInApplications: Bool {
        let path = Bundle.main.bundleURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix("\(home)/Applications/")
    }

    static var shouldOffer: Bool {
        !isInApplications && !UserDefaults.standard.bool(forKey: PrefKey.declinedMoveToApplications)
    }

    /// Copies the bundle to /Applications (or ~/Applications) and relaunches from there.
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
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
        UpdateInstaller.relaunch(at: destination)
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
