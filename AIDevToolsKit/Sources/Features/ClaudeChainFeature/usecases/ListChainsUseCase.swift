import AIOutputSDK
import ClaudeChainService
import DataPathsService
import Foundation
import GitHubService

public struct ListChainsUseCase {
    private let client: any AIClient
    private let dataPathsService: DataPathsService
    private let prService: any GitHubPRServiceProtocol
    private let repoPath: URL
    private let repoSlug: String

    public init(
        client: any AIClient,
        repoPath: URL,
        prService: any GitHubPRServiceProtocol,
        dataPathsService: DataPathsService,
        repoSlug: String
    ) {
        self.client = client
        self.dataPathsService = dataPathsService
        self.prService = prService
        self.repoPath = repoPath
        self.repoSlug = repoSlug
    }

    public func stream() -> AsyncThrowingStream<ChainListResult, Error> {
        AsyncThrowingStream { [self] continuation in
            Task {
                // Cold-open: read from disk cache instantly before any network call.
                // Swallowing intentionally: cached data is best-effort; a failure here just
                // means no stale results are shown before the fresh fetch completes.
                if let cached = coldOpen(), !cached.projects.isEmpty {
                    continuation.yield(cached)
                }

                let remoteSource = GitHubChainProjectSource(
                    gitHubPRService: prService,
                    dataPathsService: dataPathsService,
                    repoSlug: repoSlug
                )
                let service = ClaudeChainService(
                    client: client,
                    localSource: LocalChainProjectSource(repoPath: repoPath),
                    remoteSource: remoteSource
                )
                do {
                    let fresh = try await service.listChains(source: .remote, useCache: false)
                    continuation.yield(fresh)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func coldOpen() -> ChainListResult? {
        let repoDir = dataPathsService.rootPath
            .appendingPathComponent("services")
            .appendingPathComponent("claude-chain-service")
            .appendingPathComponent(repoSlug)

        guard let subdirs = try? FileManager.default.contentsOfDirectory(
            at: repoDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        var projects: [ChainProject] = []
        for subdir in subdirs {
            guard (try? subdir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectName = subdir.lastPathComponent
            let cache = ChainProjectCache(projectDirectory: subdir)
            guard (try? cache.readDescriptor()).flatMap({ $0 }) != nil else { continue }
            if let project = parseProject(name: projectName, from: cache) {
                projects.append(project)
            }
        }

        guard !projects.isEmpty else { return nil }
        return ChainListResult(projects: projects.sorted { $0.name < $1.name })
    }

    private func parseProject(name: String, from cache: ChainProjectCache) -> ChainProject? {
        let specBasePath = "\(ClaudeChainConstants.projectDirectoryPrefix)/\(name)"
        let sweepBasePath = "\(ClaudeChainConstants.sweepChainDirectory)/\(name)"
        let specChainSpecPath = "\(specBasePath)/\(ClaudeChainConstants.specFileName)"
        let sweepChainSpecPath = "\(sweepBasePath)/\(ClaudeChainConstants.specFileName)"

        let basePath: String
        let specPath: String
        let configPath: String
        let kind: ChainKind
        let specContent: String

        // Try spec chain path first, then sweep chain path.
        if let content = (try? cache.readFile(at: specChainSpecPath)).flatMap({ $0 }) {
            basePath = specBasePath
            specPath = specChainSpecPath
            configPath = "\(specBasePath)/configuration.yml"
            kind = .spec
            specContent = content
        } else if let content = (try? cache.readFile(at: sweepChainSpecPath)).flatMap({ $0 }) {
            basePath = sweepBasePath
            specPath = sweepChainSpecPath
            configPath = "\(sweepBasePath)/configuration.yml"
            kind = .sweep
            specContent = content
        } else {
            return nil
        }

        let configContent = (try? cache.readFile(at: configPath)).flatMap { $0 }
        let project = Project(name: name, basePath: basePath)
        let maxOpenPRs = configContent.flatMap { content in
            try? ProjectConfiguration.fromYAMLString(project: project, yamlContent: content).maxOpenPRs
        }

        guard !specContent.isEmpty else {
            return ChainProject(
                name: name,
                specPath: specPath,
                tasks: [],
                completedTasks: 0,
                pendingTasks: 0,
                totalTasks: 0,
                isGitHubOnly: true,
                kind: kind,
                maxOpenPRs: maxOpenPRs
            )
        }

        let spec = SpecContent(project: project, content: specContent)
        let tasks = spec.tasks.map { ChainTask(index: $0.index, description: $0.description, isCompleted: $0.isCompleted) }
        return ChainProject(
            name: name,
            specPath: specPath,
            tasks: tasks,
            completedTasks: spec.completedTasks,
            pendingTasks: spec.pendingTasks,
            totalTasks: spec.totalTasks,
            kind: kind,
            maxOpenPRs: maxOpenPRs
        )
    }
}
