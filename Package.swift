// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusFlow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "FocusFlow",
            path: "Sources/FocusFlow",
            exclude: ["Info.plist", "AppIcon.icns"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .executableTarget(
            name: "FocusFlow2",
            path: "Sources/FocusFlow2",
            exclude: ["Info.plist", "AppIcon.icns"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
