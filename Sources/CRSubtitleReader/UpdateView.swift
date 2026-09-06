import SwiftUI
import AppKit

struct UpdateView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
    }

    @ViewBuilder
    private var content: some View {
        switch state.updates.state {
        case .idle, .checking:
            Text("Checking for updates…").font(.title3).accessibilityAddTraits(.isHeader)
            ProgressView()
        case .upToDate(let date):
            Text("You're up to date").font(.title3).accessibilityAddTraits(.isHeader)
            Text("\(AppInfo.name) \(AppInfo.version) is the latest version. Checked \(date.shortDescription).")
            Button("OK") { state.updates.showUpdateWindow = false }.keyboardShortcut(.defaultAction)
        case .noReleases:
            Text("No releases yet").font(.title3).accessibilityAddTraits(.isHeader)
            Text("No published release was found on GitHub. You are running version \(AppInfo.version).")
            HStack {
                Button("Open Releases Page") { NSWorkspace.shared.open(AppInfo.releasesPageURL) }
                Button("OK") { state.updates.showUpdateWindow = false }.keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            Text("Update failed").font(.title3).accessibilityAddTraits(.isHeader)
            Text(message)
            HStack {
                Button("Try Again") { Task { await state.updates.check(userInitiated: true) } }
                Button("Open Releases Page") { NSWorkspace.shared.open(AppInfo.releasesPageURL) }
                Button("Close") { state.updates.showUpdateWindow = false }.keyboardShortcut(.cancelAction)
            }
        case .available(let release):
            releaseHeader(release)
            notes(release)
            HStack {
                Button("Install Update") { Task { await state.updates.install(release) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(release.assetURL == nil)
                Button("Later") { state.updates.showUpdateWindow = false }
                Button("Skip This Version") { state.updates.skip(release) }
                Spacer()
                Button("View on GitHub") { NSWorkspace.shared.open(release.pageURL) }
            }
            if release.assetURL == nil {
                Text("This release has no app archive attached; download it from the release page.")
                    .foregroundStyle(.secondary)
            }
        case .downloading(let release, let progress):
            releaseHeader(release)
            ProgressView(value: progress) {
                Text("Downloading \(release.assetName ?? "update")… \(Int(progress * 100))%")
            }
            .accessibilityValue("\(Int(progress * 100)) percent")
        case .installing(let release):
            releaseHeader(release)
            ProgressView { Text("Installing version \(release.version)… The app will relaunch automatically.") }
        }
    }

    private func releaseHeader(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(AppInfo.name) \(release.version) is available").font(.title3).accessibilityAddTraits(.isHeader)
            Text("You have version \(AppInfo.version).\(release.publishedAt.map { " Released \($0.shortDescription)." } ?? "")\(release.assetSize.map { " Download size: \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))." } ?? "")")
                .foregroundStyle(.secondary)
        }
    }

    private func notes(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Release notes").font(.headline).accessibilityAddTraits(.isHeader)
            ScrollView {
                Text(renderedNotes(release.notes))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140)
            .border(Color.secondary.opacity(0.3))
        }
    }

    private func renderedNotes(_ markdown: String) -> AttributedString {
        let text = markdown.isEmpty ? "No release notes were provided." : markdown
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}
