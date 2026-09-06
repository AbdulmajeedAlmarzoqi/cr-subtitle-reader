import Foundation
import AppKit
import Combine

enum ProbeResult: Equatable {
    case unknown
    case ok
    case disabled
    case notRunning
    case noWindow
    case notAuthorized
    case error(String)

    var label: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .ok: return "Enabled"
        case .disabled: return "Disabled"
        case .notRunning: return "Not running"
        case .noWindow: return "No Safari window is open"
        case .notAuthorized: return "CR Subtitle Reader is not allowed to control it. Allow it in System Settings > Privacy & Security > Automation"
        case .error(let message): return "Error: \(message)"
        }
    }
}

enum ScriptActivity: Equatable {
    case unknown
    case active(version: String, language: String, cues: Int)
    case notActive
    case noCrunchyrollTab
    case cannotVerify

    var label: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .active(let version, let language, let cues):
            let lang = language.isEmpty ? "no subtitle language yet" : "language \(language)"
            return "Active (script \(version), \(lang), \(cues) lines loaded)"
        case .notActive: return "Not running on the current Crunchyroll page"
        case .noCrunchyrollTab: return "No Crunchyroll tab is active in Safari's front window"
        case .cannotVerify: return "Cannot verify: Safari is blocking JavaScript from Apple Events, or CR Subtitle Reader is not allowed to control Safari (System Settings > Privacy & Security > Automation)"
        }
    }
}

/// Everything the setup wizard and dashboard need to know about the environment.
@MainActor
final class PrerequisiteChecker: ObservableObject {
    @Published private(set) var userscriptsInstalled = false
    @Published private(set) var scriptsDirectory: URL = ScriptInstaller.resolvedDirectory()
    @Published private(set) var scriptsDirectoryExists = false
    @Published private(set) var installedScriptVersion: String?
    @Published private(set) var bundledScriptVersion: String? = ScriptInstaller.bundledVersion()
    @Published private(set) var voiceOverRunning = false
    @Published private(set) var safariJavaScript: ProbeResult = .unknown
    @Published private(set) var voiceOverControl: ProbeResult = .unknown
    @Published private(set) var scriptActivity: ScriptActivity = .unknown
    /// Whether the script in the current Crunchyroll tab is announcing (nil when unknown).
    @Published private(set) var pageReadingEnabled: Bool?

    private let bridge: AppleScriptBridge

    init(bridge: AppleScriptBridge) {
        self.bridge = bridge
        refreshLocal()
    }

    var scriptInstalled: Bool { installedScriptVersion != nil }

    var scriptUpToDate: Bool {
        guard let installed = installedScriptVersion, let bundled = bundledScriptVersion else { return false }
        return !SemanticVersion.isNewer(bundled, than: installed)
    }

    /// Fast, side-effect-free checks (files and running apps).
    func refreshLocal() {
        userscriptsInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppInfo.userscriptsBundleIdentifier) != nil
        scriptsDirectory = ScriptInstaller.resolvedDirectory()
        scriptsDirectoryExists = ScriptInstaller.directoryExists(scriptsDirectory)
        installedScriptVersion = ScriptInstaller.installedVersion(in: scriptsDirectory)
        bundledScriptVersion = ScriptInstaller.bundledVersion()
        voiceOverRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.VoiceOver").isEmpty
    }

    /// Asks Safari to run a trivial script. Safari must be running with a window.
    func probeSafari() {
        let result = bridge.probeSafariJavaScript()
        switch result {
        case "enabled": safariJavaScript = .ok
        case "disabled": safariJavaScript = .disabled
        case "not-running": safariJavaScript = .notRunning
        case "no-window": safariJavaScript = .noWindow
        case "not-authorized": safariJavaScript = .notAuthorized
        default: safariJavaScript = .error(result)
        }
    }

    /// Checks AppleScript control of VoiceOver. Silent by default; `spoken` says a short phrase.
    func probeVoiceOver(spoken: Bool = false) {
        refreshLocal()
        let result = spoken ? bridge.probeVoiceOver(phrase: "VoiceOver access is ready.") : bridge.probeVoiceOverSilent()
        switch result {
        case "enabled": voiceOverControl = .ok
        case "disabled": voiceOverControl = .disabled
        case "not-running": voiceOverControl = .notRunning
        case "not-authorized": voiceOverControl = .notAuthorized
        default: voiceOverControl = .error(result)
        }
    }

    /// Reads the userscript's diagnostic state from the active Crunchyroll tab.
    func probeScript() {
        let state = bridge.scriptState()
        if state.isEmpty {
            // Distinguish "no tab" from "blocked" from "not injected".
            let probe = bridge.probeSafariJavaScript()
            if probe == "disabled" || probe == "not-authorized" { scriptActivity = .cannotVerify; return }
            let payload = (try? bridge.readBridge()) ?? ""
            let activity: ScriptActivity = payload.isEmpty ? .noCrunchyrollTab : .notActive
            if activity != scriptActivity { Log.info("Script activity: \(activity.label)") }
            scriptActivity = activity
            pageReadingEnabled = nil
            return
        }
        guard let data = state.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            scriptActivity = .notActive
            return
        }
        let version = json["version"] as? String ?? "?"
        let language = json["currentLang"] as? String ?? ""
        let cues = json["cues"] as? Int ?? 0
        pageReadingEnabled = json["enabled"] as? Bool
        let activity = ScriptActivity.active(version: version, language: language, cues: cues)
        if activity != scriptActivity { Log.info("Script activity: \(activity.label)") }
        scriptActivity = activity
    }

    var safariRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty
    }

    /// Reloads the active Crunchyroll tab so Safari injects a newly enabled extension.
    func reloadCrunchyrollTab() {
        _ = bridge.reloadTab()
    }

    func openUserscriptsInAppStore() {
        if !NSWorkspace.shared.open(AppInfo.userscriptsAppStoreURL) {
            NSWorkspace.shared.open(AppInfo.userscriptsWebURL)
        }
    }

    func openUserscriptsApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppInfo.userscriptsBundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openSafari() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// System Settings > Privacy & Security > Automation, where Apple Events permissions live.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func openVoiceOverUtility() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.VoiceOverUtility") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "VoiceOver Utility"]
            try? process.run()
        }
    }

    /// Opens a URL in Safari through the bridge (so it lands in the front window's current tab).
    func openInSafari(_ url: URL) {
        do {
            try bridge.openInSafari(url)
        } catch {
            NSWorkspace.shared.open(url)
        }
    }
}
