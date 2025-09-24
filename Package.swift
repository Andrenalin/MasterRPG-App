// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ModulesRPG",
    platforms: [.iOS(.v26), .macOS(.v26), .tvOS(.v26), .visionOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CoreRPG",
            targets: ["CoreRPG"]
        ),
        .library(
            name: "CoreExternalRPG",
            targets: ["CoreExternalRPG"]
        ),
        .library(
            name: "DiceRPG",
            targets: ["DiceRPG"]
        ),
        .library(
            name: "PdfRPG",
            targets: ["PdfRPG"]
        ),
        .library(
            name: "RPGResources",
            targets: ["RPGResources"]
        ),

    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CoreRPG",
            dependencies: ["CoreExternalRPG"],
            path: "Modules/CoreRPG"
        ),
        .target(
            name: "CoreExternalRPG",
            path: "Modules/CoreExternalRPG"
        ),
        .target(
            name: "DiceRPG",
            dependencies: ["CoreRPG", "CoreExternalRPG", "RPGResources"],
            path: "Modules/DiceRPG"
        ),
        .target(
            name: "PdfRPG",
            dependencies: ["CoreRPG", "CoreExternalRPG", "RPGResources"],
            path: "Modules/PdfRPG"
        ),
        .target(
            name: "RPGResources",
            dependencies: [],
            path: "Resources/RPGResources"
        ),

    ]
)
