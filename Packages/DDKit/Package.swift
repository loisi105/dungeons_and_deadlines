// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DDKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .library(name: "DDPersistence", targets: ["DDPersistence"]),
        .library(name: "DDIntents", targets: ["DDIntents"]),
        .library(name: "DDDesign", targets: ["DDDesign"]),
        .library(name: "DDSync", targets: ["DDSync"]),
    ],
    targets: [
        .target(name: "GameCore"),
        .target(name: "DDPersistence", dependencies: ["GameCore"]),
        .target(name: "DDIntents", dependencies: ["DDPersistence", "GameCore", "DDDesign"]),
        .target(name: "DDDesign", dependencies: ["GameCore"]),
        .target(name: "DDSync", dependencies: ["GameCore", "DDPersistence"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
        .testTarget(name: "DDPersistenceTests", dependencies: ["DDPersistence"]),
        .testTarget(name: "DDIntentsTests", dependencies: ["DDIntents", "DDPersistence"]),
        .testTarget(name: "DDDesignTests", dependencies: ["DDDesign", "GameCore"]),
        .testTarget(name: "DDSyncTests", dependencies: ["DDSync", "DDPersistence", "GameCore"]),
    ]
)
