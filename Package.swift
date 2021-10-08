// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SimpleAVPlayer",
    platforms: [
        .iOS(.v12),
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
