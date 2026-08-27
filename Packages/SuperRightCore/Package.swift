// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SuperRightCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SuperRightCore", targets: ["SuperRightCore"])
    ],
    targets: [
        .target(name: "SuperRightCore"),
        .testTarget(
            name: "SuperRightCoreTests",
            dependencies: ["SuperRightCore"]
        )
    ]
)
