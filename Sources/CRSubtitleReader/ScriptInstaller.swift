import Foundation
import AppKit

/// Installs the bundled userscript into the Userscripts extension's scripts folder.
enum ScriptInstaller {
    struct InstallResult {
        let destination: URL
        let version: String
        let removedLegacyFiles: [String]
    }

    enum InstallError: LocalizedError {
        case bundledScriptMissing
        case noDirectory

        var errorDescription: String? {
            switch self {
            case .bundledScriptMissing: return "The userscript is missing from the app bundle."
            case .noDirectory: return "No Userscripts folder is known yet. Install the Userscripts extension first or choose the folder manually."
            }
        }
    }

    /// Candidate default folders, most likely first. Userscripts 4.x keeps its scripts in the
    /// *extension* container; older versions used the app container.
    static func defaultDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
        return [
            containers.appendingPathComponent("\(AppInfo.userscriptsExtensionBundleIdentifier)/Data/Documents/scripts", isDirectory: true),
            containers.appendingPathComponent("\(AppInfo.userscriptsBundleIdentifier)/Data/Documents/scripts", isDirectory: true),
        ]
    }

    static var customDirectory: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: PrefKey.customScriptsDirectory), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: PrefKey.customScriptsDirectory)
        }
    }

    /// The folder scripts should be installed to: the user's choice, else the first existing default,
    /// else the primary default (which will be created on install).
    static func resolvedDirectory() -> URL {
        if let custom = customDirectory { return custom }
        let defaults = defaultDirectories()
        if let existing = defaults.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }
        return defaults[0]
    }

    static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func bundledScriptURL() -> URL? {
        Bundle.main.url(forResource: "cr_subtitle_reader.user", withExtension: "js")
    }

    static func bundledVersion() -> String? {
        guard let url = bundledScriptURL() else { return nil }
        return version(ofScriptAt: url)
    }

    static func installedScriptURL(in directory: URL) -> URL? {
        let url = directory.appendingPathComponent(AppInfo.userscriptFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func installedVersion(in directory: URL) -> String? {
        guard let url = installedScriptURL(in: directory) else { return nil }
        return version(ofScriptAt: url)
    }

    /// Reads the `@version` value from a userscript header.
    static func version(ofScriptAt url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(40) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else { continue }
            let body = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("@version") {
                return body.dropFirst("@version".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func isUpToDate(in directory: URL) -> Bool {
        guard let installed = installedVersion(in: directory), let bundled = bundledVersion() else { return false }
        return !SemanticVersion.isNewer(bundled, than: installed)
    }

    /// Copies the bundled script into the folder (creating it when needed) and removes legacy copies
    /// from earlier versions so the same subtitle is never announced twice.
    @discardableResult
    static func install(to directory: URL) throws -> InstallResult {
        guard let source = bundledScriptURL() else { throw InstallError.bundledScriptMissing }
        let fm = FileManager.default
        if !directoryExists(directory) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let destination = directory.appendingPathComponent(AppInfo.userscriptFileName)
        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: .atomic)

        var removed: [String] = []
        for legacy in AppInfo.legacyUserscriptFileNames {
            let legacyURL = directory.appendingPathComponent(legacy)
            if fm.fileExists(atPath: legacyURL.path) {
                try? fm.removeItem(at: legacyURL)
                removed.append(legacy)
            }
        }
        return InstallResult(destination: destination, version: version(ofScriptAt: destination) ?? "?", removedLegacyFiles: removed)
    }

    static func revealInFinder(_ directory: URL) {
        if directoryExists(directory) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory.deletingLastPathComponent()])
        }
    }

    /// Lets the user pick the folder shown as "Save Location" in the Userscripts app.
    @MainActor
    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose the Userscripts folder"
        panel.message = "Select the folder shown as “Save Location” in the Userscripts app."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = resolvedDirectory()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        customDirectory = url
        return url
    }
}

/// Minimal semantic version comparison ("1.2.3", "v1.2.3", "1.2.3-beta.1").
enum SemanticVersion {
    static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[..<dash]) }
        return text.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// True when `candidate` is strictly newer than `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        var a = components(candidate)
        var b = components(current)
        let count = max(a.count, b.count)
        a += Array(repeating: 0, count: count - a.count)
        b += Array(repeating: 0, count: count - b.count)
        for (x, y) in zip(a, b) {
            if x != y { return x > y }
        }
        return false
    }
}
