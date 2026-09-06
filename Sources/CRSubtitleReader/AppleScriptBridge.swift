import Foundation
import AppKit

struct AppleScriptError: LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { "AppleScript error \(code): \(message)" }
}

/// Loads the bundled AppleScript bridge (CRSubtitleReaderBridge.applescript) and calls its handlers.
/// NSAppleScript is not thread-safe, so everything runs on the main actor.
@MainActor
final class AppleScriptBridge {
    private var script: NSAppleScript?
    private(set) var loadError: String?

    init() {
        load()
    }

    var isLoaded: Bool { script != nil }

    /// The AppleScript source, shown in the About window to credit the AppleScript work.
    static var bridgeSource: String? {
        guard let url = Bundle.main.url(forResource: AppInfo.bridgeScriptResourceName, withExtension: "applescript") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func load() {
        guard let source = Self.bridgeSource else {
            loadError = "The AppleScript bridge is missing from the app bundle."
            Log.error(loadError ?? "")
            return
        }
        guard let compiled = NSAppleScript(source: source) else {
            loadError = "The AppleScript bridge could not be created."
            return
        }
        var error: NSDictionary?
        if !compiled.compileAndReturnError(&error) {
            loadError = "The AppleScript bridge failed to compile: \(Self.describe(error))"
            Log.error(loadError ?? "")
            return
        }
        script = compiled
        loadError = nil
        Log.info("AppleScript bridge compiled")
    }

    private static func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func describe(_ error: NSDictionary?) -> String {
        guard let error = error else { return "unknown error" }
        let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
        let number = error[NSAppleScript.errorNumber] as? Int ?? 0
        return "\(message) (\(number))"
    }

    /// Calls a handler in the bridge script with string arguments and returns its string result.
    @discardableResult
    func call(_ handler: String, _ arguments: [String] = []) throws -> String {
        guard let script = script else {
            throw AppleScriptError(code: -1, message: loadError ?? "The AppleScript bridge is not loaded.")
        }
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(Self.fourCharCode("ascr")),
            eventID: AEEventID(Self.fourCharCode("psbr")),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setDescriptor(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(Self.fourCharCode("snam")))
        let list = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            list.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        event.setDescriptor(list, forKeyword: AEKeyword(keyDirectObject))

        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            Log.error("AppleScript handler \(handler) failed: \(number) \(message)")
            throw AppleScriptError(code: number, message: message)
        }
        return result.stringValue ?? ""
    }

    // MARK: Convenience wrappers

    func readBridge() throws -> String { try call("readBridge") }
    func speakVoiceOver(_ text: String) throws -> String { try call("speakVoiceOver", [text]) }
    func speakSystem(_ text: String) throws { try call("speakSystem", [text]) }
    func sendCommand(_ command: String) throws -> String { try call("sendCommand", [command]) }
    func clearBridge() { _ = try? call("clearBridge") }
    func probeSafariJavaScript() -> String { (try? call("probeSafariJavaScript")) ?? "error" }
    func probeVoiceOver(phrase: String) -> String { (try? call("probeVoiceOver", [phrase])) ?? "error" }
    func probeVoiceOverSilent() -> String { (try? call("probeVoiceOverSilent")) ?? "error" }
    func reloadTab() -> String { (try? call("reloadTab")) ?? "error" }
    func scriptState() -> String { (try? call("scriptState")) ?? "" }
    func openInSafari(_ url: URL) throws { try call("openInSafari", [url.absoluteString]) }
    func activateSafari() { _ = try? call("activateSafari") }
}
