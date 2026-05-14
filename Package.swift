// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppMixer",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "AppMixer",
            path: "Sources/AppMixer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
