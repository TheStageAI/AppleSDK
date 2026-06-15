// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "macos_swift_tts",
    platforms: [.macOS(.v15)],
    dependencies: [
        // This example lives inside the SDK repo, so it depends on the
        // dist-root TheStageSDK package by local path. In your own app, add
        // it from GitHub instead — see the SDK README ("Use the SDK in your
        // own app"):
        //   .package(url: "https://github.com/TheStageAI/AppleSDK.git", from: "1.0.0")
        // `name:` pins the package identity so the product reference below
        // resolves regardless of what the distribution folder is named on disk.
        .package(name: "TheStageSDK", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "macos_swift_tts",
            dependencies: [
                .product(name: "TheStageSDK", package: "TheStageSDK")
            ],
            path: "Sources/macos_swift_tts"
        )
    ]
)
