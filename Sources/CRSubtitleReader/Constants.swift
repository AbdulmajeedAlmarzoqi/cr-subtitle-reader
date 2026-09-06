import Foundation

/// Static facts about the app, the upstream projects and the external pieces it works with.
enum AppInfo {
    static let name = "CR Subtitle Reader"
    static let author = "Abdulmajeed Almarzoqi"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.abdulmajeedalmarzoqi.crsubtitlereader"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static let repositoryOwner = "AbdulmajeedAlmarzoqi"
    static let repositoryName = "cr-subtitle-reader"
    static let repositoryURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!
    static let issuesURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/issues")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases")!

    static let upstreamName = "Subtitle Reader (NVDA add-on)"
    static let upstreamAuthor = "福恩 (maxe-hsieh)"
    static let upstreamURL = URL(string: "https://github.com/maxe-hsieh/subtitle_reader")!
    static let crunchyrollMethodAuthor = "PlatinumTsuki"
    static let crunchyrollMethodURL = URL(string: "https://github.com/maxe-hsieh/subtitle_reader/pull/58")!
    static let crunchyrollMethodAuthorURL = URL(string: "https://github.com/PlatinumTsuki")!

    static let userscriptsAppStoreURL = URL(string: "macappstore://apps.apple.com/app/id1463298887")!
    static let userscriptsWebURL = URL(string: "https://apps.apple.com/app/userscripts/id1463298887")!
    static let userscriptsBundleIdentifier = "com.userscripts.macos"
    static let userscriptsExtensionBundleIdentifier = "com.userscripts.macos.Userscripts-Extension"

    static let userscriptFileName = "cr_subtitle_reader.user.js"
    static let legacyUserscriptFileNames = ["crunchyroll_subtitles_voiceover.user.js"]
    static let bridgeScriptResourceName = "CRSubtitleReaderBridge"

    static let crunchyrollURL = URL(string: "https://www.crunchyroll.com/")!
}

/// UserDefaults keys.
enum PrefKey {
    static let setupCompleted = "setupCompleted"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let systemVoiceFallback = "systemVoiceFallback"
    static let customScriptsDirectory = "customScriptsDirectory"
    static let skippedVersion = "skippedVersion"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let declinedMoveToApplications = "declinedMoveToApplications"
    static let startReadingOnLaunch = "startReadingOnLaunch"
    static let wizardStep = "wizardStep"
    static let stayInMenuBar = "stayInMenuBar"
    static let safariAccessWasOK = "safariAccessWasOK"
    static let voiceOverAccessWasOK = "voiceOverAccessWasOK"
}
