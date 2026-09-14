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
    dependencies: [
        .package(
            url: "https://github.com/ZipArchive/ZipArchive.git",
            from: "2.5.0"
        ),
    ],
    targets: [
        .binaryTarget(
            name: "TheStageCore",
            path: "Binaries/TheStageCore.xcframework"
        ),
        .target(
            name: "thestage_apple_sdk",
            dependencies: [
                "TheStageCore",
                .product(name: "ZipArchive", package: "ZipArchive"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            // `TheStageCore` is a *static* xcframework containing C++
            // (secure_bytes, codec_host, rvq, seq2seq_step, ...), so it
            // arrives with `__cxa_throw` and `__gxx_personality_v0`
            // undefined and the consumer has to supply the C++ runtime.
            // Nothing did, which surfaces only at link time and only once
            // the Swift half compiles -- so a stale module cache hid it
            // behind compile errors for as long as one was around.
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
