// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "loom",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "loom", targets: ["loom"]),
        .executable(name: "loom-demo", targets: ["loomDemo"]),
        .executable(name: "loom-browser", targets: ["loomBrowser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/standrze/weft.git", from: "0.1.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "loom",
            dependencies: [
                .product(name: "weft", package: "weft"), .product(name: "Markdown", package: "swift-markdown"),
            ]),
        .executableTarget(name: "loomDemo", dependencies: ["loom"], path: "Examples/Demo"),
        .executableTarget(name: "loomBrowser", dependencies: ["loom"], path: "Examples/Browser"),
        .testTarget(name: "loomTests", dependencies: ["loom"]),
    ]
)
