import Foundation
import Combine
import AppKit

/// Single source of truth shared by the app scenes and the app delegate.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let bridge: AppleScriptBridge
    let checker: PrerequisiteChecker
    let reader: ReaderEngine
    let updates: UpdateManager

    @Published var setupCompleted: Bool {
        didSet { UserDefaults.standard.set(setupCompleted, forKey: PrefKey.setupCompleted) }
    }
    @Published var showWizard: Bool
    @Published var installMessage: String = ""
    @Published var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    /// Keep a status item and stay running after the window closes. Off = a plain setup tool that
    /// quits with its window; subtitles are then read inside Safari only.
    @Published var stayInMenuBar: Bool {
        didSet { UserDefaults.standard.set(stayInMenuBar, forKey: PrefKey.stayInMenuBar) }
    }

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let bridge = AppleScriptBridge()
        self.bridge = bridge
        checker = PrerequisiteChecker(bridge: bridge)
        reader = ReaderEngine(bridge: bridge)
        updates = UpdateManager()
        let completed = UserDefaults.standard.bool(forKey: PrefKey.setupCompleted)
        setupCompleted = completed
        showWizard = !completed
        stayInMenuBar = UserDefaults.standard.object(forKey: PrefKey.stayInMenuBar) as? Bool ?? true

        // Re-publish nested changes so SwiftUI views observing AppState refresh.
        for publisher in [checker.objectWillChange.eraseToAnyPublisher(),
                          reader.objectWillChange.eraseToAnyPublisher(),
                          updates.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    /// Installs (or updates) the userscript into the resolved folder.
    @discardableResult
    func installScript(quiet: Bool = false) -> Bool {
        let directory = ScriptInstaller.resolvedDirectory()
        do {
            let result = try ScriptInstaller.install(to: directory)
            var message = "Installed CR Subtitle Reader \(result.version) into \(result.destination.deletingLastPathComponent().path)"
            if !result.removedLegacyFiles.isEmpty {
                message += " (removed old copies: \(result.removedLegacyFiles.joined(separator: ", ")))"
            }
            installMessage = message
            checker.refreshLocal()
            Log.info(message)
            if !quiet { Accessibility.announce("Script installed, version \(result.version).") }
            return true
        } catch {
            installMessage = "Could not install the script: \(error.localizedDescription)"
            checker.refreshLocal()
            Accessibility.announce(installMessage)
            return false
        }
    }

    func chooseScriptsFolder() {
        if ScriptInstaller.chooseDirectory() != nil {
            checker.refreshLocal()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLogin = LaunchAtLogin.isEnabled
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
            installMessage = "Could not change Launch at Login: \(error.localizedDescription)"
        }
    }

    /// Sends one of the in-page commands (toggle, language, repeat) and reports the outcome.
    func sendPageCommand(_ command: String, label: String) {
        do {
            let result = try bridge.sendCommand(command)
            if result == "no-tab" {
                Accessibility.announce("No Crunchyroll tab is active in Safari's front window.")
            } else if !reader.isRunning {
                // The userscript announces the result through its live region; nothing else to do.
            }
        } catch let error as AppleScriptError where error.code == 8 {
            Accessibility.announce("Safari is blocking JavaScript from Apple Events, so \(label) cannot be sent from the app. Use Option+Shift shortcuts inside the page instead.")
        } catch {
            Accessibility.announce("Could not send \(label): \(error.localizedDescription)")
        }
    }

    func finishSetup() {
        setupCompleted = true
        showWizard = false
        UserDefaults.standard.removeObject(forKey: PrefKey.wizardStep)
        if stayInMenuBar {
            AppWindows.closeMain()
            sayReady()
        } else {
            speakShort("Done")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NSApp.terminate(nil) }
        }
    }

    // MARK: Requirements watchdog

    struct RequirementIssue {
        let step: WizardStep
        let message: String
    }

    private var watchdog: Timer?
    private var lastPageWarning: Date?

    /// The first thing that is missing, or nil when everything needed is in place.
    /// Access permissions are only reported when they worked before (so a user who skipped
    /// the optional VoiceOver step is not nagged), or when `strict` is set.
    func findIssue(strict: Bool = false) -> RequirementIssue? {
        checker.refreshLocal()
        if !checker.userscriptsInstalled {
            return RequirementIssue(step: .userscripts, message: "The Userscripts extension is missing.")
        }
        if !checker.scriptInstalled {
            return RequirementIssue(step: .activate, message: "The subtitle script is missing from the Userscripts folder.")
        }
        let defaults = UserDefaults.standard
        if checker.safariRunning && (strict || defaults.bool(forKey: PrefKey.safariAccessWasOK)) {
            checker.probeSafari()
            switch checker.safariJavaScript {
            case .disabled: return RequirementIssue(step: .safariAccess, message: "Safari is no longer allowing JavaScript from Apple Events.")
            case .notAuthorized: return RequirementIssue(step: .safariAccess, message: "CR Subtitle Reader is no longer allowed to control Safari.")
            default: break
            }
        }
        if checker.voiceOverRunning && (strict || defaults.bool(forKey: PrefKey.voiceOverAccessWasOK)) {
            checker.probeVoiceOver()
            switch checker.voiceOverControl {
            case .disabled: return RequirementIssue(step: .voiceOverAccess, message: "VoiceOver is no longer allowing AppleScript control.")
            case .notAuthorized: return RequirementIssue(step: .voiceOverAccess, message: "CR Subtitle Reader is no longer allowed to control VoiceOver.")
            default: break
            }
        }
        return nil
    }

    /// Checks the requirements; when something is missing, says so and opens the setup assistant
    /// at the step that fixes it. Returns true when an issue was found.
    @discardableResult
    func handleIssueIfAny(strict: Bool = false) -> Bool {
        guard let issue = findIssue(strict: strict) else { return false }
        Log.error("Requirement issue: \(issue.message)")
        openWizard(at: issue.step)
        speakShort("\(issue.message) Let's fix it.")
        return true
    }

    func openWizard(at step: WizardStep) {
        UserDefaults.standard.set(step.rawValue, forKey: PrefKey.wizardStep)
        showWizard = true
        AppWindows.showMain()
    }

    /// Keeps an eye on the requirements while the app lives in the menu bar.
    func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdogTick() }
        }
    }

    private func watchdogTick() {
        guard setupCompleted, !showWizard, !AppWindows.isMainVisible else { return }
        if handleIssueIfAny() { return }
        // Script installed but not running on an open Crunchyroll episode: the extension is
        // probably off or not allowed for the site.
        guard UserDefaults.standard.bool(forKey: PrefKey.safariAccessWasOK) else { return }
        checker.probeScript()
        if case .notActive = checker.scriptActivity {
            if let last = lastPageWarning, Date().timeIntervalSince(last) < 600 { return }
            lastPageWarning = Date()
            Log.error("Script not active on the open Crunchyroll page")
            openWizard(at: .activate)
            speakShort("The subtitle script is not running on this Crunchyroll page. Let's check the extension.")
        }
    }

    // MARK: Factory reset

    /// Forgets every setting and the login item. The installed script and permissions stay.
    func factoryReset(relaunch: Bool) {
        reader.stop(announce: false)
        try? LaunchAtLogin.set(false)
        UserDefaults.standard.removePersistentDomain(forName: AppInfo.bundleIdentifier)
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at: Log.fileURL)
        if relaunch {
            UpdateInstaller.relaunch(at: Bundle.main.bundleURL)
        } else {
            NSApp.terminate(nil)
        }
    }

    // MARK: Which channel is reading right now

    /// Plain-language description of who is speaking subtitles at the moment.
    var channelDescription: String {
        if checker.pageReadingEnabled == false { return "Muted. Subtitles are not read anywhere." }
        if reader.isRunning { return "The app speaks through VoiceOver, in any application." }
        return "Safari reads the subtitles while it is the front application."
    }

    func mutePage() { sendPageCommand("mute", label: "mute") }
    func unmutePage() { sendPageCommand("unmute", label: "unmute") }

    /// Mutes when the page is currently reading, otherwise unmutes (toggle when unknown).
    func toggleMutePage() {
        switch checker.pageReadingEnabled {
        case .some(true): mutePage()
        case .some(false): unmutePage()
        case .none: sendPageCommand("toggle", label: "the mute command")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.checker.probeScript() }
    }

    /// One word through VoiceOver (falls back to an accessibility announcement).
    func sayReady() {
        speakShort("Ready")
    }

    func speakShort(_ text: String) {
        let result = (try? bridge.speakVoiceOver(text)) ?? "error"
        Log.info("speakShort via VoiceOver -> \(result): \(text)")
        if result != "ok" { Accessibility.announce(text) }
    }

    func rerunSetup() {
        UserDefaults.standard.removeObject(forKey: PrefKey.wizardStep)
        showWizard = true
        AppWindows.showMain()
    }
}
