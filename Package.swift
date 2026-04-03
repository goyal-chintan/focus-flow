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
        .testTarget(
            name: "FocusFlowTests",
            dependencies: ["FocusFlow"],
            path: "Tests/FocusFlowTests"
        )
    ]
)
