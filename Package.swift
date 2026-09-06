// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CRSubtitleReader",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CRSubtitleReader",
            path: "Sources/CRSubtitleReader",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
