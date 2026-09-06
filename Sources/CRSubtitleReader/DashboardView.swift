import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Setup status") {
                StatusLine(label: "Userscripts extension", value: state.checker.userscriptsInstalled ? "Installed" : "Not installed", ok: state.checker.userscriptsInstalled)
                HStack {
                    StatusLine(label: "CR Subtitle Reader script", value: scriptStatusText, ok: state.checker.scriptInstalled && state.checker.scriptUpToDate)
                    Spacer()
                    Button(state.checker.scriptInstalled ? (state.checker.scriptUpToDate ? "Reinstall" : "Update Script") : "Install Script") { state.installScript() }
                }
                HStack {
                    StatusLine(label: "Safari: JavaScript from Apple Events", value: state.checker.safariJavaScript.label, ok: probeOK(state.checker.safariJavaScript))
                    Spacer()
                    Button("Check") {
                        state.checker.probeSafari()
                        Accessibility.announce("Safari setting: \(state.checker.safariJavaScript.label)")
                    }
                }
                HStack {
                    StatusLine(label: "VoiceOver AppleScript control", value: state.checker.voiceOverControl.label, ok: probeOK(state.checker.voiceOverControl))
                    Spacer()
                    Button("Test") { state.checker.probeVoiceOver() }
                }
                HStack {
                    StatusLine(label: "Script on current Crunchyroll tab", value: state.checker.scriptActivity.label, ok: activityOK(state.checker.scriptActivity))
                    Spacer()
                    Button("Check") {
                        state.checker.probeScript()
                        Accessibility.announce(state.checker.scriptActivity.label)
                    }
                }
                if !state.installMessage.isEmpty {
                    Text(state.installMessage).foregroundStyle(.secondary)
                }
            }

            Section("Background reading through VoiceOver") {
                Toggle("Read subtitles through VoiceOver (works while you are in other apps)", isOn: Binding(
                    get: { state.reader.isRunning },
                    set: { $0 ? state.reader.start() : state.reader.stop() }
                ))
                Text(state.reader.status.description)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Reader status: \(state.reader.status.description)")
                if !state.reader.lastSpoken.isEmpty {
                    Text("Last line: \(state.reader.lastSpoken)")
                }
                Text("Without background reading, subtitles are still announced by VoiceOver inside Safari through a live region.")
                    .foregroundStyle(.secondary)
            }

            Section("Quick actions") {
                HStack {
                    Button("Toggle Subtitle Reading") { state.sendPageCommand("toggle", label: "the toggle command") }
                    Button("Next Subtitle Language") { state.sendPageCommand("language", label: "the language command") }
                    Button("Repeat Current Line") { state.sendPageCommand("repeat", label: "the repeat command") }
                }
                HStack {
                    Button("Open Crunchyroll in Safari") { state.checker.openInSafari(AppInfo.crunchyrollURL) }
                    Button("Show Script Folder") { ScriptInstaller.revealInFinder(state.checker.scriptsDirectory) }
                }
                Text("Inside the page you can also press Option+Shift+S (toggle), Option+Shift+L (language) and Option+Shift+R (repeat).")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Check for Updates…") { Task { await state.updates.check(userInitiated: true) } }
                    Button("Run Setup Assistant Again") { state.rerunSetup() }
                    Button("About") { AppWindows.openAbout() }
                }
                Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.checker.refreshLocal() }
        .onReceive(refreshTimer) { _ in state.checker.refreshLocal() }
    }

    private var scriptStatusText: String {
        guard let installed = state.checker.installedScriptVersion else { return "Not installed" }
        if state.checker.scriptUpToDate { return "Installed, version \(installed)" }
        return "Installed version \(installed); version \(state.checker.bundledScriptVersion ?? "?") is available"
    }

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

struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button(state.reader.isRunning ? "Stop Background Reading" : "Start Background Reading") { state.reader.toggle() }
        Divider()
        Button("Toggle Subtitle Reading in Page") { state.sendPageCommand("toggle", label: "the toggle command") }
        Button("Next Subtitle Language") { state.sendPageCommand("language", label: "the language command") }
        Button("Repeat Current Line") { state.sendPageCommand("repeat", label: "the repeat command") }
        Divider()
        Button("Open Crunchyroll in Safari") { state.checker.openInSafari(AppInfo.crunchyrollURL) }
        Button("Show \(AppInfo.name)") { AppWindows.showMainWindow() }
        Button("Check for Updates…") { Task { await state.updates.check(userInitiated: true) } }
        Divider()
        Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
    }
}
