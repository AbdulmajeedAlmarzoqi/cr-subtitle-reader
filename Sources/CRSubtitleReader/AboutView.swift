import SwiftUI
import AppKit

struct AboutView: View {
    @State private var showSource = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(AppInfo.name).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
                    }
                }
                Text("Reads Crunchyroll subtitles aloud with VoiceOver in Safari.")

                Text("Credits").font(.headline).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 8) {
                    Text("AppleScript, Safari userscript and this app developed by \(AppInfo.author).")
                    Text("Based on \(AppInfo.upstreamName) by \(AppInfo.upstreamAuthor), which pioneered reading web video subtitles with a screen reader.")
                    Text("The Crunchyroll technique (intercepting the playback response, fetching the subtitle file and exposing the active line to the screen reader) was found and implemented for NVDA by \(AppInfo.crunchyrollMethodAuthor). This project ports that work to Safari and VoiceOver.")
                }

                HStack {
                    Button("Project on GitHub") { NSWorkspace.shared.open(AppInfo.repositoryURL) }
                    Button("Subtitle Reader for NVDA") { NSWorkspace.shared.open(AppInfo.upstreamURL) }
                    Button("\(AppInfo.crunchyrollMethodAuthor)'s pull request") { NSWorkspace.shared.open(AppInfo.crunchyrollMethodURL) }
                }

                Text("License").font(.headline).accessibilityAddTraits(.isHeader)
                Text("Free and open source under the GNU General Public License v3.0 or later, like the NVDA add-on it builds on.")

                DisclosureGroup("AppleScript bridge source", isExpanded: $showSource) {
                    ScrollView {
                        Text(AppleScriptBridge.bridgeSource ?? "The AppleScript source is not available in this build.")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                    .border(Color.secondary.opacity(0.3))
                }

                Text("Copyright © 2026 \(AppInfo.author).").foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}
