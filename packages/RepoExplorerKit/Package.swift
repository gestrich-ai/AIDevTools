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
        .library(
            name: "RepoExplorerUI",
            targets: ["RepoExplorerUI"]
        ),
        .executable(
            name: "repo-explorer",
            targets: ["RepoExplorerCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
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
        .target(
            name: "RepoExplorerUI",
            dependencies: [
                "RepoExplorerFileTreeService",
                "RepoExplorerGitClient",
            ],
            path: "Sources/RepoExplorerUI"
        ),
        .executableTarget(
            name: "RepoExplorerCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "RepoExplorerFileTreeService",
            ],
            path: "Sources/RepoExplorerCLI"
        ),
    ]
)
