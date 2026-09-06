import SwiftUI
import AppKit

/// Live status after setup. Everything refreshes by itself every few seconds.
struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Status") {
                StatusLine(label: "Userscripts extension", value: state.checker.userscriptsInstalled ? "Installed" : "Not installed", ok: state.checker.userscriptsInstalled)
                HStack {
                    StatusLine(label: "Script file", value: scriptStatusText, ok: state.checker.scriptInstalled && state.checker.scriptUpToDate)
                    if !state.checker.scriptInstalled || !state.checker.scriptUpToDate {
                        Spacer()
                        Button(state.checker.scriptInstalled ? "Update Script" : "Install Script") { state.installScript() }
                    }
                }
                StatusLine(label: "Safari access", value: probeText(state.checker.safariJavaScript), ok: probeOK(state.checker.safariJavaScript))
                StatusLine(label: "VoiceOver access", value: probeText(state.checker.voiceOverControl), ok: probeOK(state.checker.voiceOverControl))
                StatusLine(label: "Script on current Crunchyroll tab", value: state.checker.scriptActivity.label, ok: activityOK(state.checker.scriptActivity))
                if !state.installMessage.isEmpty {
                    Text(state.installMessage).foregroundStyle(.secondary)
                }
            }

            Section("Who is reading right now") {
                Text(state.channelDescription)
                    .accessibilityLabel("Now: \(state.channelDescription)")
                HStack {
                    Button(state.checker.pageReadingEnabled == false ? "Unmute Subtitles" : "Mute Subtitles") { state.toggleMutePage() }
                    Button("Next Language") { state.sendPageCommand("language", label: "the language command") }
                    Button("Previous Language") { state.sendPageCommand("language-back", label: "the previous-language command") }
                    Button("Repeat Current Line") { state.sendPageCommand("repeat", label: "the repeat command") }
                }
                HStack {
                    Button(state.checker.pageInterruptMode == true ? "Turn Interrupt Mode Off" : "Turn Interrupt Mode On") {
                        state.sendPageCommand("interrupt", label: "the interrupt-mode command")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { state.checker.probeScript() }
                    }
                    Text(state.checker.pageInterruptMode == true
                         ? "On: a new line cuts off the previous one; VoiceOver plays a short tone first."
                         : "Off: lines are read one after another, without any tone.")
                        .foregroundStyle(.secondary)
                }
                Text("Muting silences the script inside Safari; it applies to both channels below.")
                    .foregroundStyle(.secondary)
            }

            Section("Speak in background") {
                Toggle("Speak subtitles through VoiceOver while you are in other applications", isOn: Binding(
                    get: { state.reader.isRunning },
                    set: { $0 ? state.reader.start() : state.reader.stop() }
                ))
                Text(state.reader.status.description)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Background status: \(state.reader.status.description)")
                if !state.reader.lastSpoken.isEmpty {
                    Text("Last line: \(state.reader.lastSpoken)")
                }
                Text("Off means Safari's own live region does the reading, which works only while Safari is the front application. On means the app reads through VoiceOver everywhere; it needs the Safari and VoiceOver access from the setup.")
                    .foregroundStyle(.secondary)
            }

            Section("More") {
                HStack {
                    Button("Open Crunchyroll in Safari") { state.checker.openInSafari(AppInfo.crunchyrollURL) }
                    Button("Automation Settings") { state.checker.openAutomationSettings() }
                    Button("Run Setup Assistant Again") { state.rerunSetup() }
                }
                Text("Inside the page: Option+Shift+S mutes or unmutes, Option+Shift+L and Option+Shift+K move to the next or previous language, Option+Shift+R repeats the line, Option+Shift+I switches interrupt mode.")
                    .foregroundStyle(.secondary)
                Text(state.stayInMenuBar ? "Closing this window keeps the app running in the menu bar." : "The app quits when you close this window. Turn on “Keep running in the menu bar” in Settings to change that.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Check for Updates…") { Task { await state.updates.check(userInitiated: true) } }
                    Button("Settings…") { AppWindows.openSettings() }
                    Button("About") { AppWindows.openAbout() }
                }
                Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        state.checker.refreshLocal()
        state.checker.probeSafari()
        state.checker.probeVoiceOver()
        state.checker.probeScript()
    }

    private var scriptStatusText: String {
        guard let installed = state.checker.installedScriptVersion else { return "Not installed" }
        if state.checker.scriptUpToDate { return "Installed, version \(installed)" }
        return "Installed version \(installed); version \(state.checker.bundledScriptVersion ?? "?") is available"
    }

    private func probeText(_ result: ProbeResult) -> String {
        switch result {
        case .ok: return "Ready"
        default: return result.label
        }
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
