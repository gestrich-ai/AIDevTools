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
            name: "RepoExplorerFileTreeService",
            targets: ["RepoExplorerFileTreeService"]
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
            name: "RepoExplorerFileTreeService",
            dependencies: [
                "RepoExplorerDataPathsService",
            ],
            path: "Sources/RepoExplorerFileTreeService"
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
