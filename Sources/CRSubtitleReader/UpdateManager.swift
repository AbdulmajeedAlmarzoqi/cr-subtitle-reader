import Foundation
import AppKit
import Combine

struct ReleaseInfo: Equatable {
    let version: String
    let tag: String
    let title: String
    let notes: String
    let pageURL: URL
    let publishedAt: Date?
    let assetURL: URL?
    let assetName: String?
    let assetSize: Int64?
}

/// Checks GitHub Releases for a newer version, downloads the zipped app and replaces the running copy.
@MainActor
final class UpdateManager: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(checkedAt: Date)
        case available(ReleaseInfo)
        case downloading(ReleaseInfo, progress: Double)
        case installing(ReleaseInfo)
        case failed(String)
        case noReleases
    }

    @Published private(set) var state: State = .idle
    @Published var showUpdateWindow = false
    @Published private(set) var lastCheck: Date? = UserDefaults.standard.object(forKey: PrefKey.lastUpdateCheck) as? Date

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: PrefKey.autoCheckUpdates) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PrefKey.autoCheckUpdates) }
    }

    private var periodicTimer: Timer?
    private var downloadDelegate: DownloadDelegate?

    var availableRelease: ReleaseInfo? {
        switch state {
        case .available(let release), .downloading(let release, _), .installing(let release): return release
        default: return nil
        }
    }

    // MARK: Scheduling

    func startAutomaticChecks() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.autoCheckEnabled else { return }
                Task { await self.check(userInitiated: false) }
            }
        }
        guard autoCheckEnabled else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < 20 * 3600 { return }
        Task { await check(userInitiated: false) }
    }

    // MARK: Checking

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            lastCheck = Date()
            UserDefaults.standard.set(lastCheck, forKey: PrefKey.lastUpdateCheck)
            guard let release = release else {
                state = .noReleases
                if userInitiated { showUpdateWindow = true }
                return
            }
            if SemanticVersion.isNewer(release.version, than: AppInfo.version) {
                let skipped = UserDefaults.standard.string(forKey: PrefKey.skippedVersion)
                state = .available(release)
                if userInitiated || skipped != release.version {
                    showUpdateWindow = true
                    Accessibility.announce("CR Subtitle Reader \(release.version) is available.")
                }
            } else {
                state = .upToDate(checkedAt: Date())
                if userInitiated { showUpdateWindow = true }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if userInitiated { showUpdateWindow = true }
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: AppInfo.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.httpStatus(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UpdateError.badResponse }
        let tag = json["tag_name"] as? String ?? ""
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zipAsset = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }
        let formatter = ISO8601DateFormatter()
        return ReleaseInfo(
            version: version,
            tag: tag,
            title: json["name"] as? String ?? tag,
            notes: json["body"] as? String ?? "",
            pageURL: URL(string: json["html_url"] as? String ?? "") ?? AppInfo.releasesPageURL,
            publishedAt: (json["published_at"] as? String).flatMap { formatter.date(from: $0) },
            assetURL: (zipAsset?["browser_download_url"] as? String).flatMap { URL(string: $0) },
            assetName: zipAsset?["name"] as? String,
            assetSize: (zipAsset?["size"] as? NSNumber)?.int64Value
        )
    }

    func skip(_ release: ReleaseInfo) {
        UserDefaults.standard.set(release.version, forKey: PrefKey.skippedVersion)
        showUpdateWindow = false
        state = .idle
    }

    // MARK: Installing

    func install(_ release: ReleaseInfo) async {
        guard let assetURL = release.assetURL else {
            state = .failed("This release has no downloadable app archive. Open the release page to download it manually.")
            return
        }
        state = .downloading(release, progress: 0)
        Accessibility.announce("Downloading update \(release.version).")
        do {
            let zipURL = try await download(assetURL) { [weak self] progress in
                self?.state = .downloading(release, progress: progress)
            }
            state = .installing(release)
            Accessibility.announce("Installing update.")
            let newAppURL = try await Task.detached(priority: .userInitiated) {
                try UpdateInstaller.extractApp(from: zipURL, expectedVersion: release.version)
            }.value
            try UpdateInstaller.replaceRunningApp(with: newAppURL)
            Accessibility.announce("Update installed. CR Subtitle Reader will now relaunch.")
            UpdateInstaller.relaunch(at: Bundle.main.bundleURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        downloadDelegate = delegate
        defer { downloadDelegate = nil }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            var request = URLRequest(url: url)
            request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            session.downloadTask(with: request).resume()
        }
    }
}

enum UpdateError: LocalizedError {
    case badResponse
    case httpStatus(Int)
    case noAppInArchive
    case wrongBundle(String)
    case versionMismatch(expected: String, found: String)
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "GitHub returned an unexpected response."
        case .httpStatus(let code): return "GitHub returned HTTP status \(code)."
        case .noAppInArchive: return "The downloaded archive does not contain an app."
        case .wrongBundle(let id): return "The downloaded app has an unexpected identifier (\(id))."
        case .versionMismatch(let expected, let found): return "The downloaded app reports version \(found), expected \(expected)."
        case .notWritable(let path): return "The app cannot replace itself at \(path). Move CR Subtitle Reader to your Applications folder and try again, or download the update manually."
        }
    }
}

/// Receives download progress and completion for UpdateManager.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let progress: @MainActor (Double) -> Void
    var continuation: CheckedContinuation<URL, Error>?

    init(progress: @escaping @MainActor (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.progress(value) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this method returns, so move it first.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("crsr-update-\(UUID().uuidString)")
            .appendingPathExtension("zip")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                continuation?.resume(throwing: UpdateError.httpStatus(http.statusCode))
            } else {
                continuation?.resume(returning: destination)
            }
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

/// File-level steps of an update: unzip, validate, swap bundles, relaunch.
enum UpdateInstaller {
    static func extractApp(from zipURL: URL, expectedVersion: String) throws -> URL {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("crsr-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, workDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.noAppInArchive }

        guard let appURL = findApp(in: workDir, depth: 0) else { throw UpdateError.noAppInArchive }
        guard let bundle = Bundle(url: appURL) else { throw UpdateError.noAppInArchive }
        let identifier = bundle.bundleIdentifier ?? ""
        guard identifier == AppInfo.bundleIdentifier else { throw UpdateError.wrongBundle(identifier) }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard !SemanticVersion.isNewer(expectedVersion, than: version) else {
            throw UpdateError.versionMismatch(expected: expectedVersion, found: version)
        }
        removeQuarantine(appURL)
        return appURL
    }

    private static func findApp(in directory: URL, depth: Int) -> URL? {
        guard depth < 3,
              let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        for item in items {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue,
               let app = findApp(in: item, depth: depth + 1) {
                return app
            }
        }
        return nil
    }

    private static func removeQuarantine(_ url: URL) {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? xattr.run()
        xattr.waitUntilExit()
    }

    /// Swaps the running bundle with the new one. The old copy goes to the Trash.
    static func replaceRunningApp(with newAppURL: URL) throws {
        let fm = FileManager.default
        let currentURL = Bundle.main.bundleURL
        let parent = currentURL.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else { throw UpdateError.notWritable(parent.path) }

        let backupURL = parent.appendingPathComponent(".\(currentURL.lastPathComponent).old-\(UUID().uuidString)")
        try fm.moveItem(at: currentURL, to: backupURL)
        do {
            try fm.moveItem(at: newAppURL, to: currentURL)
        } catch {
            // Cross-volume move failed: copy instead.
            do {
                try fm.copyItem(at: newAppURL, to: currentURL)
            } catch {
                try? fm.moveItem(at: backupURL, to: currentURL)
                throw error
            }
        }
        var trashed: NSURL?
        if (try? fm.trashItem(at: backupURL, resultingItemURL: &trashed)) == nil {
            try? fm.removeItem(at: backupURL)
        }
    }

    /// Relaunches the app at `url` after this process exits.
    static func relaunch(at url: URL) {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", url.path]
        try? shell.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}
