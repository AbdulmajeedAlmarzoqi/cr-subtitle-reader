import Foundation
import AppKit

/// `crsr://` URLs let VoiceOver Commander, Shortcuts or the Terminal drive the app without UI:
///   crsr://reader/start | stop | toggle      background reading through VoiceOver
///   crsr://page/mute | unmute | toggle       silence or resume the script in the Crunchyroll tab
///   crsr://page/language | repeat            next subtitle language / repeat the current line
///   crsr://page/interrupt                    interrupt mode on/off (assertive live region, with VoiceOver's tone)
///   crsr://update/check                      check for updates and show the result
///   crsr://setup                             open the setup assistant
///   crsr://show                              bring the main window to the front
/// Example: open -g "crsr://reader/toggle"
@MainActor
enum URLCommands {
    static func handle(_ url: URL, state: AppState) {
        Log.info("URL command received: \(url.absoluteString)")
        guard url.scheme?.lowercased() == "crsr" else { return }
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        switch parts {
        case ["reader", "start"]: state.reader.start()
        case ["reader", "stop"]: state.reader.stop()
        case ["reader", "toggle"]: state.reader.toggle()
        case ["page", "toggle"]: state.toggleMutePage()
        case ["page", "mute"]: state.mutePage()
        case ["page", "unmute"]: state.unmutePage()
        case ["page", "language"]: state.sendPageCommand("language", label: "the language command")
        case ["page", "interrupt"]: state.sendPageCommand("interrupt", label: "the interrupt-mode command")
        case ["page", "repeat"]: state.sendPageCommand("repeat", label: "the repeat command")
        case ["update", "check"]: Task { await state.updates.check(userInitiated: true) }
        case ["setup"]: state.rerunSetup(); AppWindows.showMain()
        case ["show"]: AppWindows.showMain()
        default: Accessibility.announce("Unknown CR Subtitle Reader command: \(url.absoluteString)")
        }
    }
}

/// Command-line options, mainly for automated testing:
///   --skip-relocation        never offer to move the app to /Applications
///   --auto-install-update    install an available update without confirmation (testing only)
///   --reset                  forget all settings and the login item, then quit (factory reset)
enum LaunchOptions {
    static let skipRelocation = CommandLine.arguments.contains("--skip-relocation")
    static let autoInstallUpdate = CommandLine.arguments.contains("--auto-install-update")
    static let reset = CommandLine.arguments.contains("--reset")
}
