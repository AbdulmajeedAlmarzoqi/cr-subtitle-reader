import Foundation
import AppKit

/// `crsr://` URLs let VoiceOver Commander, Shortcuts or the Terminal drive the app without UI:
///   crsr://reader/start | stop | toggle      background reading through VoiceOver
///   crsr://page/toggle | language | repeat   commands for the userscript in the Crunchyroll tab
///   crsr://update/check                      check for updates and show the result
///   crsr://setup                             open the setup assistant
///   crsr://show                              bring the main window to the front
/// Example: open -g "crsr://reader/toggle"
@MainActor
enum URLCommands {
    static func handle(_ url: URL, state: AppState) {
        guard url.scheme?.lowercased() == "crsr" else { return }
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        switch parts {
        case ["reader", "start"]: state.reader.start()
        case ["reader", "stop"]: state.reader.stop()
        case ["reader", "toggle"]: state.reader.toggle()
        case ["page", "toggle"]: state.sendPageCommand("toggle", label: "the toggle command")
        case ["page", "language"]: state.sendPageCommand("language", label: "the language command")
        case ["page", "repeat"]: state.sendPageCommand("repeat", label: "the repeat command")
        case ["update", "check"]: Task { await state.updates.check(userInitiated: true) }
        case ["setup"]: state.rerunSetup(); AppWindows.showMainWindow()
        case ["show"]: AppWindows.showMainWindow()
        default: Accessibility.announce("Unknown CR Subtitle Reader command: \(url.absoluteString)")
        }
    }
}

/// Command-line options, mainly for automated testing:
///   --skip-relocation        never offer to move the app to /Applications
///   --auto-install-update    install an available update without confirmation (testing only)
enum LaunchOptions {
    static let skipRelocation = CommandLine.arguments.contains("--skip-relocation")
    static let autoInstallUpdate = CommandLine.arguments.contains("--auto-install-update")
}
