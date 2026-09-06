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
                Toggle("Keep running in the menu bar (needed for speaking in the background)", isOn: $state.stayInMenuBar)
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .disabled(!state.stayInMenuBar)
                Toggle("Start speaking in the background as soon as the app launches", isOn: $startReadingOnLaunch)
                    .disabled(!state.stayInMenuBar)
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
                Button("Reset CR Subtitle Reader…") { confirmReset() }
                Text("Forgets every setting and runs the setup assistant again. The script and permissions are kept.")
                    .foregroundStyle(.secondary)
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
        .frame(minWidth: 560, minHeight: 520)
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset CR Subtitle Reader?"
        alert.informativeText = "All settings are forgotten and the app relaunches with the setup assistant."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            state.factoryReset(relaunch: true)
        }
    }
}
