import Foundation
import Combine

/// Background reading: polls the userscript through the AppleScript bridge and speaks new lines
/// with VoiceOver. Mirrors the standalone stay-open applet.
@MainActor
final class ReaderEngine: ObservableObject {
    enum Status: Equatable {
        case stopped
        case waitingForCrunchyroll
        case reading
        case javaScriptBlocked
        case scriptMissing
        case voiceOverUnavailable
        case notAuthorized

        var description: String {
            switch self {
            case .stopped: return "Stopped"
            case .waitingForCrunchyroll: return "Running. Waiting for a Crunchyroll tab in Safari's front window."
            case .reading: return "Reading subtitles."
            case .javaScriptBlocked: return "Safari is blocking JavaScript from Apple Events. Enable it in Safari Settings, Developer tab."
            case .scriptMissing: return "The userscript is not running on this page. Check the Userscripts extension for crunchyroll.com."
            case .voiceOverUnavailable: return "VoiceOver cannot be controlled with AppleScript. Using the system voice instead."
            case .notAuthorized: return "macOS has not allowed CR Subtitle Reader to control Safari. Open System Settings > Privacy & Security > Automation and enable Safari and VoiceOver for CR Subtitle Reader."
            }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastSpoken = ""
    @Published private(set) var linesSpoken = 0

    var systemVoiceFallback: Bool {
        UserDefaults.standard.object(forKey: PrefKey.systemVoiceFallback) as? Bool ?? true
    }

    private let bridge: AppleScriptBridge
    private var timer: Timer?
    private var lastSeq = ""
    private var primed = false
    private var lastNoScriptWarning: Date?
    private var lastJSWarning: Date?
    private var voiceOverWarned = false

    private let pollInterval: TimeInterval = 0.2
    private let idleInterval: TimeInterval = 1.5
    private let warningCooldown: TimeInterval = 60

    init(bridge: AppleScriptBridge) {
        self.bridge = bridge
    }

    func start(announce: Bool = true) {
        guard !isRunning else { return }
        isRunning = true
        primed = false
        lastSeq = ""
        voiceOverWarned = false
        status = .waitingForCrunchyroll
        Log.info("Reader started")
        if announce {
            speak("CR Subtitle Reader started. Open an episode in Safari and I will read its subtitles.")
        }
        schedule(after: 0.1)
    }

    func stop(announce: Bool = true) {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil
        bridge.clearBridge()
        isRunning = false
        status = .stopped
        if announce {
            speak("CR Subtitle Reader stopped.")
        }
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRunning else { return }
        let payload: String
        do {
            payload = try bridge.readBridge()
        } catch let error as AppleScriptError {
            Log.error("readBridge failed: \(error.code) \(error.message)")
            if error.code == 8 || error.message.contains("Apple Events") {
                warnJavaScriptBlocked()
                schedule(after: 5)
            } else if error.code == -1743 {
                warnNotAuthorized()
                schedule(after: 5)
            } else {
                schedule(after: 2)
            }
            return
        } catch {
            schedule(after: 2)
            return
        }

        if payload.isEmpty {
            if status == .reading || status == .scriptMissing { status = .waitingForCrunchyroll }
            schedule(after: idleInterval)
            return
        }

        let parts = payload.components(separatedBy: "\t")
        guard parts.count >= 4 else {
            schedule(after: pollInterval)
            return
        }
        let isWatchPage = parts[0] == "1"
        let heartbeatAge = Double(parts[1]) ?? -1
        let seq = parts[2]
        let message = parts[3...].joined(separator: " ")

        if isWatchPage && (heartbeatAge < 0 || heartbeatAge > 5000) {
            warnScriptMissing()
        } else if status != .voiceOverUnavailable {
            status = .reading
        }

        if !primed {
            primed = true
            lastSeq = seq
            schedule(after: pollInterval)
            return
        }

        if !seq.isEmpty && seq != lastSeq {
            lastSeq = seq
            if !message.isEmpty {
                lastSpoken = message
                linesSpoken += 1
                speak(message)
            }
        }
        schedule(after: pollInterval)
    }

    /// Speaks through VoiceOver, falling back to the system voice when allowed.
    func speak(_ text: String) {
        let result = (try? bridge.speakVoiceOver(text)) ?? "error"
        Log.info("speak via VoiceOver -> \(result): \(text.prefix(60))")
        if result == "ok" { return }
        if (result == "disabled" || result == "not-authorized") && !voiceOverWarned {
            voiceOverWarned = true
            status = result == "not-authorized" ? .notAuthorized : .voiceOverUnavailable
        }
        if systemVoiceFallback {
            try? bridge.speakSystem(text)
        }
    }

    private func warnJavaScriptBlocked() {
        status = .javaScriptBlocked
        if let last = lastJSWarning, Date().timeIntervalSince(last) < warningCooldown { return }
        lastJSWarning = Date()
        speak("Safari is blocking JavaScript from Apple Events. Enable it in Safari Settings, Developer tab.")
    }

    private var lastAuthWarning: Date?
    private func warnNotAuthorized() {
        status = .notAuthorized
        if let last = lastAuthWarning, Date().timeIntervalSince(last) < warningCooldown { return }
        lastAuthWarning = Date()
        speak("macOS has not allowed CR Subtitle Reader to control Safari. Open System Settings, Privacy and Security, Automation, and enable Safari and VoiceOver for CR Subtitle Reader.")
    }

    private func warnScriptMissing() {
        status = .scriptMissing
        if let last = lastNoScriptWarning, Date().timeIntervalSince(last) < warningCooldown { return }
        lastNoScriptWarning = Date()
        speak("The CR Subtitle Reader script is not running on this page. Make sure the Userscripts extension is enabled for crunchyroll.com.")
    }
}
