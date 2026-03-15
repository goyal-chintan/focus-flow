// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusFlow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "FocusFlow",
            path: "Sources/FocusFlow",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
