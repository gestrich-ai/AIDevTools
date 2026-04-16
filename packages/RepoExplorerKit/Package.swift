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
        .library(
            name: "RepoExplorerGitClient",
            targets: ["RepoExplorerGitClient"]
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
        .target(
            name: "RepoExplorerGitClient",
            dependencies: [
                "RepoExplorerCLITools",
            ],
            path: "Sources/RepoExplorerGitClient"
        ),
    ]
)
