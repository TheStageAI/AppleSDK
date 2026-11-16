// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TheStageSDK",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        // The one product apps depend on. `import TheStageSDK` re-exports
        // everything (it does `@_exported import TheStageCore`).
        .library(
            name: "TheStageSDK",
            targets: ["TheStageSDK"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "TheStageCore",
            path: "./TheStageCore.xcframework"
        ),
        .target(
            name: "TheStageSDK",
            // TheStageCore is a dynamic framework that links everything
            // it needs; Xcode embeds it in the app.
            dependencies: ["TheStageCore"],
            path: "Sources/TheStageSDK"
        ),
    ]
)
