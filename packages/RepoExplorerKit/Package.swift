// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RepoExplorerKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "repo-explorer",
            targets: ["RepoExplorerCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "RepoExplorerCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/RepoExplorerCLI"
        ),
    ]
)
