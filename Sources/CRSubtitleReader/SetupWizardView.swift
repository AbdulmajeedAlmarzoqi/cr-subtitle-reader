import SwiftUI
import AppKit

enum WizardStep: Int, CaseIterable {
    case welcome, userscripts, installScript, enableExtension, safariJavaScript, voiceOverControl, verify, finish

    var number: Int { rawValue + 1 }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .userscripts: return "Install the Userscripts extension"
        case .installScript: return "Install the CR Subtitle Reader script"
        case .enableExtension: return "Turn on Userscripts in Safari"
        case .safariJavaScript: return "Allow JavaScript from Apple Events"
        case .voiceOverControl: return "Allow AppleScript to control VoiceOver"
        case .verify: return "Verify on Crunchyroll"
        case .finish: return "All set"
        }
    }

    var isOptional: Bool {
        switch self {
        case .safariJavaScript, .voiceOverControl, .verify: return true
        default: return false
        }
    }
}

struct SetupWizardView: View {
    @EnvironmentObject private var state: AppState
    @State private var step: WizardStep = .welcome
    @State private var verifying = false
    @State private var verifyMessage = ""
    @State private var autoInstallAttempted = false
    @AppStorage(PrefKey.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(PrefKey.startReadingOnLaunch) private var startReadingOnLaunch = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
                Button("Back") { move(to: -1) }
                    .disabled(step == .welcome)
                Spacer()
                if step.isOptional {
                    Button("Skip") { move(to: 1) }
                }
                Button(step == .finish ? "Finish" : "Continue") {
                    if step == .finish { state.finishSetup() } else { move(to: 1) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(24)
        .onAppear {
            state.checker.refreshLocal()
        }
        .onReceive(refreshTimer) { _ in
            if step == .userscripts || step == .installScript { state.checker.refreshLocal() }
        }
        .onChange(of: step) { newStep in
            Accessibility.announce("Step \(newStep.number) of \(WizardStep.allCases.count): \(newStep.title)")
            if newStep == .installScript && !autoInstallAttempted {
                autoInstallAttempted = true
                if state.checker.userscriptsInstalled { state.installScript() }
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .userscripts: return state.checker.userscriptsInstalled
        case .installScript: return state.checker.scriptInstalled
        default: return true
        }
    }

    private func move(to delta: Int) {
        guard let next = WizardStep(rawValue: step.rawValue + delta) else { return }
        step = next
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcome
        case .userscripts: userscripts
        case .installScript: installScript
        case .enableExtension: enableExtension
        case .safariJavaScript: safariJavaScript
        case .voiceOverControl: voiceOverControl
        case .verify: verify
        case .finish: finish
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CR Subtitle Reader lets VoiceOver read Crunchyroll subtitles in Safari.")
            Text("Crunchyroll draws its subtitles as pixels, so screen readers never see them. A small script inside the page fetches the subtitle file, follows the video and announces every line. This assistant installs everything for you in a few steps:")
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Install the free Userscripts extension from the App Store.")
                Text("2. Let this app place the CR Subtitle Reader script into the extension.")
                Text("3. Turn the extension on in Safari and allow it on crunchyroll.com.")
                Text("4. Optionally, allow AppleScript access so the app can read in the background.")
            }
            Text("Press Continue to begin.")
        }
    }

    private var userscripts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Userscripts is a free, open-source Safari extension that runs the CR Subtitle Reader script on Crunchyroll pages.")
            StatusLine(label: "Userscripts app", value: state.checker.userscriptsInstalled ? "Installed" : "Not installed", ok: state.checker.userscriptsInstalled)
            HStack {
                Button("Open Userscripts in the App Store") { state.checker.openUserscriptsInAppStore() }
                Button("Check Again") { state.checker.refreshLocal() }
            }
            if !state.checker.userscriptsInstalled {
                Text("After installing, come back here. This page checks automatically every few seconds.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Great, Userscripts is installed. Press Continue.")
            }
        }
    }

    private var installScript: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The script is copied into the folder the Userscripts extension reads from. Nothing else on your Mac is changed.")
            StatusLine(label: "Folder", value: state.checker.scriptsDirectory.path, ok: state.checker.scriptsDirectoryExists)
            StatusLine(label: "Script", value: state.checker.installedScriptVersion.map { "Installed, version \($0)" } ?? "Not installed", ok: state.checker.scriptInstalled)
            HStack {
                Button(state.checker.scriptInstalled ? "Reinstall Script" : "Install Script") { state.installScript() }
                Button("Choose Folder…") { state.chooseScriptsFolder() }
                Button("Show in Finder") { ScriptInstaller.revealInFinder(state.checker.scriptsDirectory) }
            }
            if !state.installMessage.isEmpty {
                Text(state.installMessage).foregroundStyle(.secondary)
            }
            Text("If you changed the “Save Location” inside the Userscripts app, use Choose Folder to point at that folder.")
                .foregroundStyle(.secondary)
        }
    }

    private var enableExtension: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Safari extensions are off until you enable them. Do this once:")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open Safari and press Command+Comma to open Settings.")
                Text("2. Go to the Extensions tab and turn on Userscripts.")
                Text("3. Still in the Extensions tab, select Userscripts and set crunchyroll.com to “Allow” or choose “Allow on Every Website”.")
                Text("4. Alternatively, open crunchyroll.com, press the Userscripts button in Safari's toolbar and choose “Always Allow on This Website”.")
            }
            HStack {
                Button("Open Safari") { state.checker.openSafari() }
                Button("Open Crunchyroll in Safari") { state.checker.openInSafari(AppInfo.crunchyrollURL) }
                Button("Open the Userscripts App") { state.checker.openUserscriptsApp() }
            }
            Text("The Userscripts app has an “Open Safari Settings” button that jumps straight to the Extensions tab.")
                .foregroundStyle(.secondary)
        }
    }

    private var safariJavaScript: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional, but recommended. This Safari setting lets the app talk to the page: it enables background reading through VoiceOver, the quick actions in the menu bar, and automatic verification.")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. In Safari, press Command+Comma and open the Advanced tab.")
                Text("2. Turn on “Show features for web developers”.")
                Text("3. A Developer tab appears. Open it and turn on “Allow JavaScript from Apple Events”.")
            }
            StatusLine(label: "Safari setting", value: state.checker.safariJavaScript.label, ok: probeOK(state.checker.safariJavaScript))
            HStack {
                Button("Open Safari") { state.checker.openSafari() }
                Button("Check Now") {
                    state.checker.probeSafari()
                    Accessibility.announce("Safari setting: \(state.checker.safariJavaScript.label)")
                }
            }
            Text("Safari must be open with at least one window for the check to work.")
                .foregroundStyle(.secondary)
        }
    }

    private var voiceOverControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional. With this VoiceOver setting the app can speak subtitles through VoiceOver itself, using your voice, rate and braille display, even while you are in another app.")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open VoiceOver Utility (VO-F8, or from Applications > Utilities).")
                Text("2. In the General category, turn on “Allow VoiceOver to be controlled with AppleScript”.")
            }
            StatusLine(label: "VoiceOver control", value: state.checker.voiceOverControl.label, ok: probeOK(state.checker.voiceOverControl))
            HStack {
                Button("Open VoiceOver Utility") { state.checker.openVoiceOverUtility() }
                Button("Test Now") { state.checker.probeVoiceOver() }
            }
            Text("The test speaks a short sentence through VoiceOver when it succeeds.")
                .foregroundStyle(.secondary)
        }
    }

    private var verify: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Let's make sure the script is running. This opens crunchyroll.com in Safari and asks the page whether CR Subtitle Reader is active. It needs the Safari setting from the previous step; without it, simply open an episode and listen.")
            StatusLine(label: "Script on Crunchyroll", value: state.checker.scriptActivity.label, ok: activityOK(state.checker.scriptActivity))
            HStack {
                Button(verifying ? "Verifying…" : "Open Crunchyroll and Verify") { runVerification() }
                    .disabled(verifying)
                Button("Check Current Tab") {
                    state.checker.probeScript()
                    Accessibility.announce(state.checker.scriptActivity.label)
                }
            }
            if !verifyMessage.isEmpty {
                Text(verifyMessage).foregroundStyle(.secondary)
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything is in place. Open any episode on Crunchyroll in Safari and VoiceOver will read the subtitles as they appear.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcuts inside the Crunchyroll page:")
                Text("• Option+Shift+S: turn subtitle reading on or off")
                Text("• Option+Shift+L: switch to the next subtitle language")
                Text("• Option+Shift+R: repeat the current line")
            }
            Toggle("Launch CR Subtitle Reader at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
            Toggle("Start background reading through VoiceOver when the app launches", isOn: $startReadingOnLaunch)
            Text("You can change these later in Settings (Command+Comma). Press Finish to open the dashboard.")
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

    private func runVerification() {
        verifying = true
        verifyMessage = "Opening Crunchyroll in Safari…"
        state.checker.openInSafari(AppInfo.crunchyrollURL)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            state.checker.probeScript()
            verifying = false
            switch state.checker.scriptActivity {
            case .active:
                verifyMessage = "The CR Subtitle Reader script is running on Crunchyroll. You are ready to go."
            case .notActive:
                verifyMessage = "Safari opened Crunchyroll but the script is not running. Check that Userscripts is turned on in Safari Settings > Extensions and allowed on crunchyroll.com, then verify again."
            case .cannotVerify:
                verifyMessage = "Safari is blocking JavaScript from Apple Events, so the app cannot ask the page. Enable the setting from the previous step, or just open an episode and listen."
            case .noCrunchyrollTab:
                verifyMessage = "Crunchyroll is not the active tab in Safari's front window. Switch to it and press Check Current Tab."
            case .unknown:
                verifyMessage = ""
            }
            Accessibility.announce(verifyMessage)
        }
    }
}
