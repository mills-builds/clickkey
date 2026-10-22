// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClickKey",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClickKey",
            path: "Sources/ClickKey"
        )
    ]
)
