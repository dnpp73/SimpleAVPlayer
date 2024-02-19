// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "SimpleAVPlayer",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "SimpleAVPlayer", targets: ["SimpleAVPlayer"]),
    ],
    targets: [
        .target(
            name: "SimpleAVPlayer",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
