// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "thestage_apple_sdk",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "thestage-apple-sdk",
            targets: ["thestage_apple_sdk"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "TheStageCore",
            path: "Binaries/TheStageCore.xcframework"
        ),
        .target(
            name: "thestage_apple_sdk",
            // `TheStageCore` is a dynamic framework that links what it
            // needs (C++ runtime, zip); Xcode embeds it in the app.
            dependencies: ["TheStageCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
