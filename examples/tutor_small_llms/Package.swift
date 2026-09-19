// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "tutor_small_llms",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Pinned to the AppleSDK git tag stamped by `make_dist.sh --version=…`.
        // Do not use a local path here — CI and customers must exercise the
        // published tag.
        .package(
            url: "https://github.com/TheStageAI/AppleSDK.git",
            exact: Version(1, 4, 1)
        )
    ],
    targets: [
        .executableTarget(
            name: "tutor_small_llms",
            dependencies: [
                .product(name: "TheStageSDK", package: "AppleSDK")
            ],
            path: "Sources/tutor_small_llms"
        )
    ]
)
