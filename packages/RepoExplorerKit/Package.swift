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
        .library(
            name: "RepoExplorerDataPathsService",
            targets: ["RepoExplorerDataPathsService"]
        ),
    ],
    targets: [
        .target(
            name: "RepoExplorerCLITools",
            dependencies: [],
            path: "Sources/RepoExplorerCLITools"
        ),
        .target(
            name: "RepoExplorerDataPathsService",
            dependencies: [],
            path: "Sources/RepoExplorerDataPathsService"
        ),
    ]
)
