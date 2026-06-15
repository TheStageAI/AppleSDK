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
            path: "Binaries/TheStageCore.xcframework"
        ),
        .target(
            name: "thestage_apple_sdk",
            dependencies: [
                "TheStageCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "ZipArchive", package: "ZipArchive"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
