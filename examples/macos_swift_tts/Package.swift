// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "macos_swift_tts",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Pinned to the AppleSDK git tag stamped by `make_dist.sh --version=…`.
        // Do not use a local path here — CI and customers must exercise the
        // published tag.
        .package(
            url: "https://github.com/TheStageAI/AppleSDK.git",
            exact: Version(1, 2, 0)
        )
    ],
    targets: [
        .executableTarget(
            name: "macos_swift_tts",
            dependencies: [
                .product(name: "TheStageSDK", package: "AppleSDK")
            ],
            path: "Sources/macos_swift_tts"
        )
    ]
)
