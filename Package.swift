// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TheStageSDK",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "TheStageSDK",
            targets: ["TheStageSDK"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift.git",
            exact: "0.30.6"
        ),
        .package(
            url: "https://github.com/ZipArchive/ZipArchive.git",
            from: "2.5.0"
        ),
    ],
    targets: [
        .binaryTarget(
            name: "TheStageCore",
            path: "./TheStageCore.xcframework"
        ),
        .target(
            name: "TheStageSDK",
            dependencies: [
                "TheStageCore",
                .product(name: "MLX", package: "mlx-swift"),
                // TheStageCore links SSZipArchive (engine-archive
                // extraction); consumers must provide it when linking.
                .product(name: "ZipArchive", package: "ZipArchive"),
            ],
            path: "Sources/TheStageSDK"
        ),
    ]
)
