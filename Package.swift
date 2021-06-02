// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "minecraft-jar-command",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(
            name: "minecraft-jar-command",
            targets: ["minecraft-jar-command"]
        ),
        .library(name: "MojangAuthentication", targets: ["MojangAuthentication"]),
        .library(name: "InstallationManager", targets: ["InstallationManager"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "0.3.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "1.1.2"),
        .package(url: "https://github.com/marmelroy/Zip.git", from: "2.1.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "minecraft-jar-command",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "MojangAuthentication"),
                .target(name: "InstallationManager")
            ]
        ),
        .target(
            name: "InstallationManager",
            dependencies: [
                .product(name: "Zip", package: "Zip"),
                .product(name: "Crypto", package: "swift-crypto"),
                .target(name: "Common"),
                .target(name: "MojangRules")
            ]
        ),
        .target(
            name: "MojangAuthentication",
            dependencies: [
                .target(name: "Common")
            ]
        ),
        .target(
            name: "MojangRules",
            dependencies: [

            ]
        ),
        .target(
            name: "Common",
            dependencies: [

            ]
        ),
    ]
)
