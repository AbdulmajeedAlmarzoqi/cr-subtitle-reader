import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(PrefKey.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(PrefKey.systemVoiceFallback) private var systemVoiceFallback = true
    @AppStorage(PrefKey.startReadingOnLaunch) private var startReadingOnLaunch = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Toggle("Start background reading through VoiceOver when the app launches", isOn: $startReadingOnLaunch)
                Toggle("Use the system voice when VoiceOver cannot be controlled", isOn: $systemVoiceFallback)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                HStack {
                    Button("Check for Updates Now") { Task { await state.updates.check(userInitiated: true) } }
                    if let last = state.updates.lastCheck {
                        Text("Last checked \(last.shortDescription)").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Diagnostics") {
                Button("Reveal Log File") { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
                Text(Log.fileURL.path).foregroundStyle(.secondary)
            }
            Section("Script folder") {
                Text(state.checker.scriptsDirectory.path)
                    .textSelection(.enabled)
                    .accessibilityLabel("Script folder: \(state.checker.scriptsDirectory.path)")
                HStack {
                    Button("Change…") { state.chooseScriptsFolder() }
                    Button("Use Default") {
                        ScriptInstaller.customDirectory = nil
                        state.checker.refreshLocal()
                    }
                    Button("Reinstall Script") { state.installScript() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding()
    }
}
