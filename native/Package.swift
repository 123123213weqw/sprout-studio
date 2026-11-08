// swift-tools-version:5.9
// SproutKit — .sprout 工程格式的纯 Swift 移植(与 dist/music.js 语义 1:1,Linux 可测)。
import PackageDescription

let package = Package(
    name: "SproutKit",
    targets: [
        .target(
            name: "SproutKit",
            resources: [.copy("Resources/tables.json"), .copy("Resources/samples.json")]
        ),
        .target(
            name: "SproutAudio",
            dependencies: ["SproutKit"]
        ),
        .executableTarget(
            name: "sproutkit-cli",
            dependencies: ["SproutKit", "SproutAudio"],
            path: "Sources/sproutkit-cli"
        ),
        .testTarget(
            name: "SproutKitTests",
            dependencies: ["SproutKit"]
        ),
        .testTarget(
            name: "SproutAudioTests",
            dependencies: ["SproutAudio"]
        ),
    ]
)
