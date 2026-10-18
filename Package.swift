// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "loom",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "loom", targets: ["loom"]),
        .executable(name: "loom-demo", targets: ["loomDemo"]),
        .executable(name: "loom-browser", targets: ["loomBrowser"]),
        .executable(name: "loom-widgets", targets: ["loomWidgets"]),
        .executable(name: "loom-viewports", targets: ["loomViewports"]),
    ],
    dependencies: [
        .package(url: "https://github.com/standrze/weft.git", revision: "b65b817a46973b5752cb4ca14ed5f94c2b57a244"),
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
        .executableTarget(name: "loomWidgets", dependencies: ["loom"], path: "Examples/Widgets"),
        .executableTarget(
            name: "loomViewports", dependencies: ["loom", .product(name: "weft", package: "weft")],
            path: "Examples/Viewports"),
        .testTarget(name: "loomTests", dependencies: ["loom"]),
    ]
)
