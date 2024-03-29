// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "minecraft-jar-command",
	platforms: [
		.macOS("12")
	],
	products: [
		.library(name: "InstallationManager", targets: ["InstallationManager"]),
		.library(name: "Common", targets: ["Common"])
	],
	dependencies: [
		// Dependencies declare other packages that this package depends on.
		.package(url: "https://github.com/apple/swift-crypto.git", from: "1.1.2"),
		.package(url: "https://github.com/marmelroy/Zip.git", from: "2.1.0")
	],
	targets: [
		// Targets are the basic building blocks of a package. A target can define a module or a test suite.
		// Targets can depend on other targets in this package, and on products in packages this package depends on.
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
			name: "MojangRules",
			dependencies: [
				
			]
		),
		.target(
			name: "Common",
			dependencies: [
				.product(name: "Crypto", package: "swift-crypto"),
			]
		),
	]
)
