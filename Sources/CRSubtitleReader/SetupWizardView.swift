import SwiftUI
import AppKit

enum WizardStep: Int, CaseIterable {
    case welcome, userscripts, safariAccess, voiceOverAccess, activate, finish

    var number: Int { rawValue + 1 }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .userscripts: return "Install the Userscripts extension"
        case .safariAccess: return "Safari access"
        case .voiceOverAccess: return "VoiceOver access"
        case .activate: return "Turn on the script in Safari"
        case .finish: return "All set"
        }
    }
}

/// Step-by-step setup. Every step checks its own requirement continuously, so the user only
/// follows the instructions and presses Continue; there are no "check" buttons.
struct SetupWizardView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(PrefKey.wizardStep) private var stepIndex = 0
    @AppStorage(PrefKey.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(PrefKey.startReadingOnLaunch) private var startReadingOnLaunch = false

    @State private var lastAnnouncement = ""
    @State private var openedCrunchyroll = false
    @State private var lastReload: Date?
    @State private var voiceOverConfirmed = false

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var step: WizardStep { WizardStep(rawValue: stepIndex) ?? .welcome }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step \(step.number) of \(WizardStep.allCases.count): \(step.title)")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Back") { go(to: stepIndex - 1) }
                    .disabled(step == .welcome)
                Spacer()
                Button(step == .finish ? "Finish" : "Continue") {
                    if step == .finish { state.finishSetup() } else { go(to: stepIndex + 1) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(24)
        .onAppear {
            state.checker.refreshLocal()
            enter(step)
        }
        .onReceive(timer) { _ in tick() }
    }

    private var canContinue: Bool {
        switch step {
        case .userscripts: return state.checker.userscriptsInstalled
        default: return true
        }
    }

    private func go(to index: Int) {
        guard let next = WizardStep(rawValue: index) else { return }
        stepIndex = next.rawValue
        Accessibility.announce("Step \(next.number) of \(WizardStep.allCases.count): \(next.title)")
        enter(next)
    }

    /// Work that starts as soon as a step is shown.
    private func enter(_ step: WizardStep) {
        lastAnnouncement = ""
        switch step {
        case .safariAccess:
            if !state.checker.safariRunning { state.checker.openSafari() }
            state.checker.probeSafari()
        case .voiceOverAccess:
            voiceOverConfirmed = false
            state.checker.probeVoiceOver()
        case .activate:
            openedCrunchyroll = false
            lastReload = nil
            state.checker.refreshLocal()
            if !state.checker.scriptInstalled || !state.checker.scriptUpToDate { state.installScript() }
            state.checker.probeSafari()
            startActivationWatch()
        default:
            break
        }
        tick()
    }

    /// Runs every two seconds and keeps the current step's status fresh.
    private func tick() {
        switch step {
        case .userscripts:
            state.checker.refreshLocal()
            if state.checker.userscriptsInstalled { announceOnce("Userscripts is installed. Press Continue.") }
        case .safariAccess:
            state.checker.probeSafari()
            if state.checker.safariJavaScript == .ok { announceOnce("Safari access is ready. Press Continue.") }
        case .voiceOverAccess:
            state.checker.probeVoiceOver()
            if state.checker.voiceOverControl == .ok && !voiceOverConfirmed {
                voiceOverConfirmed = true
                state.speakShort("VoiceOver access is ready. Press Continue.")
            }
        case .activate:
            state.checker.refreshLocal()
            if !state.checker.scriptInstalled { state.installScript() }
            if state.checker.safariJavaScript != .ok { state.checker.probeSafari() }
            guard state.checker.safariJavaScript == .ok else { return }
            if !openedCrunchyroll { startActivationWatch(); return }
            state.checker.probeScript()
            switch state.checker.scriptActivity {
            case .active:
                announceOnce("The script is running on Crunchyroll. Press Continue.")
            case .noCrunchyrollTab:
                startActivationWatch()
            case .notActive:
                // Safari only injects a newly enabled extension into freshly loaded pages.
                if let last = lastReload, Date().timeIntervalSince(last) < 12 { return }
                lastReload = Date()
                state.checker.reloadCrunchyrollTab()
            default:
                break
            }
        default:
            break
        }
    }

    private func startActivationWatch() {
        guard state.checker.safariJavaScript == .ok else { return }
        state.checker.openInSafari(AppInfo.crunchyrollURL)
        openedCrunchyroll = true
        lastReload = Date()
    }

    private func announceOnce(_ text: String) {
        guard text != lastAnnouncement else { return }
        lastAnnouncement = text
        Accessibility.announce(text)
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcome
        case .userscripts: userscripts
        case .safariAccess: safariAccess
        case .voiceOverAccess: voiceOverAccess
        case .activate: activate
        case .finish: finish
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CR Subtitle Reader lets VoiceOver read Crunchyroll subtitles in Safari.")
            Text("Crunchyroll draws its subtitles as pixels, so screen readers never see them. A small script inside the page fetches the subtitle file, follows the video and announces every line. This assistant sets everything up in a few steps and checks each one for you automatically.")
            Text("When macOS asks whether CR Subtitle Reader may control Safari or VoiceOver, choose Allow. Press Continue to begin.")
        }
    }

    private var userscripts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Userscripts is a free, open-source Safari extension that runs the CR Subtitle Reader script on Crunchyroll pages. Install it from the App Store, then come back: this page notices the installation by itself.")
            StatusLine(label: "Userscripts app", value: state.checker.userscriptsInstalled ? "Installed" : "Not installed yet", ok: state.checker.userscriptsInstalled)
            Button("Open Userscripts in the App Store") { state.checker.openUserscriptsInAppStore() }
        }
    }

    private var safariAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CR Subtitle Reader talks to Safari to verify the setup and to read subtitles in the background. Two things are needed, and this page checks them continuously:")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. If macOS asks whether CR Subtitle Reader may control Safari, choose Allow.")
                Text("2. In Safari, press Command+Comma, open the Advanced tab and turn on “Show features for web developers”. Then open the new Developer tab and turn on “Allow JavaScript from Apple Events”.")
            }
            StatusLine(label: "Safari access", value: safariStatusText, ok: probeOK(state.checker.safariJavaScript))
            HStack {
                Button("Open Safari") { state.checker.openSafari() }
                Button("Open Automation Settings") { state.checker.openAutomationSettings() }
            }
        }
    }

    private var safariStatusText: String {
        switch state.checker.safariJavaScript {
        case .ok: return "Ready"
        case .disabled: return "Waiting: turn on “Allow JavaScript from Apple Events” in Safari's Developer settings"
        case .notAuthorized: return "Waiting: allow CR Subtitle Reader to control Safari (System Settings > Privacy & Security > Automation)"
        case .notRunning: return "Waiting for Safari to open"
        case .noWindow: return "Waiting: open a Safari window"
        case .unknown: return "Checking…"
        case .error(let message): return "Error: \(message)"
        }
    }

    private var voiceOverAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("With this permission the app can speak through VoiceOver itself, using your voice, rate and braille display, even while you are in another app. This page checks continuously:")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. If macOS asks whether CR Subtitle Reader may control VoiceOver, choose Allow.")
                Text("2. Open VoiceOver Utility (VO-F8), choose General and turn on “Allow VoiceOver to be controlled with AppleScript”.")
            }
            StatusLine(label: "VoiceOver access", value: voiceOverStatusText, ok: probeOK(state.checker.voiceOverControl))
            HStack {
                Button("Open VoiceOver Utility") { state.checker.openVoiceOverUtility() }
                Button("Open Automation Settings") { state.checker.openAutomationSettings() }
            }
            Text("You can skip this step: subtitles are still read inside Safari without it.")
                .foregroundStyle(.secondary)
        }
    }

    private var voiceOverStatusText: String {
        switch state.checker.voiceOverControl {
        case .ok: return "Ready"
        case .disabled: return "Waiting: turn on “Allow VoiceOver to be controlled with AppleScript” in VoiceOver Utility"
        case .notAuthorized: return "Waiting: allow CR Subtitle Reader to control VoiceOver (System Settings > Privacy & Security > Automation)"
        case .notRunning: return "VoiceOver is not running"
        case .unknown: return "Checking…"
        case .noWindow: return "Checking…"
        case .error(let message): return "Error: \(message)"
        }
    }

    private var activate: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The script has been placed in the Userscripts folder. Now turn the extension on; Crunchyroll is open in Safari and this page notices as soon as the script starts running:")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. In Safari, press Command+Comma and open the Extensions tab. Turn on Userscripts.")
                Text("2. Select Userscripts in the list and allow it for crunchyroll.com, or choose “Allow on Every Website”.")
            }
            StatusLine(label: "Script file", value: state.checker.installedScriptVersion.map { "Installed, version \($0)" } ?? "Not installed", ok: state.checker.scriptInstalled)
            StatusLine(label: "Script on Crunchyroll", value: activationStatusText, ok: activityOK(state.checker.scriptActivity))
            HStack {
                Button("Open Safari") { state.checker.openSafari() }
                Button("Open Crunchyroll") { startActivationWatch() }
                Button("Choose Script Folder…") { state.chooseScriptsFolder() }
            }
            Text("Folder: \(state.checker.scriptsDirectory.path)")
                .foregroundStyle(.secondary)
            if !state.installMessage.isEmpty {
                Text(state.installMessage).foregroundStyle(.secondary)
            }
        }
    }

    private var activationStatusText: String {
        if state.checker.safariJavaScript != .ok {
            return "Cannot verify without Safari access (step 3). Finish the two steps above, then open an episode and listen."
        }
        switch state.checker.scriptActivity {
        case .active(let version, _, _): return "Running (version \(version))"
        case .notActive: return "Waiting for the extension to be turned on and allowed for crunchyroll.com…"
        case .noCrunchyrollTab: return "Opening crunchyroll.com in Safari…"
        case .cannotVerify: return "Waiting for Safari access…"
        case .unknown: return "Checking…"
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything is ready. Open any episode on Crunchyroll in Safari and VoiceOver reads the subtitles as they appear, as long as Safari is the front application.")
            Text("Keeping the app in the menu bar adds “Speak in Background”: the app then reads through VoiceOver while you are in other applications, and offers mute, language and update commands from the menu bar. If you only listen inside Safari, you can let the app quit after setup.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcuts inside the Crunchyroll page:")
                Text("• Option+Shift+S: turn subtitle reading on or off")
                Text("• Option+Shift+L: switch to the next subtitle language")
                Text("• Option+Shift+R: repeat the current line")
            }
            Toggle("Keep CR Subtitle Reader running in the menu bar after setup", isOn: $state.stayInMenuBar)
            Toggle("Launch CR Subtitle Reader at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            .disabled(!state.stayInMenuBar)
            Toggle("Start speaking in the background as soon as the app launches", isOn: $startReadingOnLaunch)
                .disabled(!state.stayInMenuBar)
            Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
            Text(state.stayInMenuBar
                 ? "Press Finish: the window closes and the app waits in the menu bar. Closing or minimizing the window later keeps it running; Command+Q quits it."
                 : "Press Finish: the app quits. Open it again whenever you want to check the setup or change a setting.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func probeOK(_ result: ProbeResult) -> Bool? {
        switch result {
        case .unknown: return nil
        case .ok: return true
        default: return false
        }
    }

    private func activityOK(_ activity: ScriptActivity) -> Bool? {
        switch activity {
        case .unknown: return nil
        case .active: return true
        default: return false
        }
    }
}
