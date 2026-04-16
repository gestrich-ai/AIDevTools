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
            name: "RepoExplorerGitClient",
            targets: ["RepoExplorerGitClient"]
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
            name: "RepoExplorerGitClient",
            dependencies: [
                "RepoExplorerCLITools",
            ],
            path: "Sources/RepoExplorerGitClient"
        ),
        .executableTarget(
            name: "RepoExplorerCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/RepoExplorerCLI"
        ),
    ]
)
