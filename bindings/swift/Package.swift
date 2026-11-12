// swift-tools-version:6.0
// The bindings' Swift side: `TheStageBridge` (routes over the public SDK, one
// mapping for every host language) and `thestage-host` (the macOS process the
// Python package drives). Builds against the TheStageSDK package at the root
// of this repository.
import PackageDescription

let package = Package(
    name: "TheStageBindings",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TheStageBridge", targets: ["TheStageBridge"]),
        .executable(name: "thestage-host", targets: ["thestage-host"]),
    ],
    dependencies: [
        .package(name: "TheStageSDK", path: "../.."),
    ],
    targets: [
        .target(
            name: "TheStageBridge",
            dependencies: [.product(name: "TheStageSDK", package: "TheStageSDK")],
            path: "Sources/TheStageBridge"
        ),
        .executableTarget(
            name: "thestage-host",
            dependencies: ["TheStageBridge"],
            path: "Sources/thestage-host",
            // Its own bundle identity: the SDK keys its keychain items by
            // bundle, so the host owns its entries instead of reading the
            // shared command-line ones (which asked for keychain access).
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                "-Xlinker", "Resources/thestage-host-Info.plist",
            ])]
        ),
    ]
)
