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

            Section("Background reading through VoiceOver") {
                Toggle("Read subtitles through VoiceOver, even while you are in other apps", isOn: Binding(
                    get: { state.reader.isRunning },
                    set: { $0 ? state.reader.start() : state.reader.stop() }
                ))
                Text(state.reader.status.description)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Reader status: \(state.reader.status.description)")
                if !state.reader.lastSpoken.isEmpty {
                    Text("Last line: \(state.reader.lastSpoken)")
                }
            }

            Section("Actions") {
                HStack {
                    Button("Toggle Subtitle Reading") { state.sendPageCommand("toggle", label: "the toggle command") }
                    Button("Next Subtitle Language") { state.sendPageCommand("language", label: "the language command") }
                    Button("Repeat Current Line") { state.sendPageCommand("repeat", label: "the repeat command") }
                }
                HStack {
                    Button("Open Crunchyroll in Safari") { state.checker.openInSafari(AppInfo.crunchyrollURL) }
                    Button("Automation Settings") { state.checker.openAutomationSettings() }
                    Button("Run Setup Assistant Again") { state.rerunSetup() }
                }
                Text("Inside the page: Option+Shift+S toggles reading, Option+Shift+L switches language, Option+Shift+R repeats the line. Closing this window keeps the app running in the menu bar.")
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
