// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RepoExplorerKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RepoExplorerCLITools",
            targets: ["RepoExplorerCLITools"]
        ),
    ],
    targets: [
        .target(
            name: "RepoExplorerCLITools",
            dependencies: [],
            path: "Sources/RepoExplorerCLITools"
        ),
    ]
)
