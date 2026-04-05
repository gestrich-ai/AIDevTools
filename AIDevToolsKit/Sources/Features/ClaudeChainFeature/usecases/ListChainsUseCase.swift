import ClaudeChainService
import Foundation
import UseCaseSDK

// Local discovery only finds chains present on disk in the current checkout.
// Chain definitions typically live on feature branches; callers that need to
// enumerate all chains across branches should use ListChainsFromGitHubUseCase.
// This use case is only appropriate when the caller has already checked out
// the relevant branch (e.g., inside RunSpecChainTaskUseCase).
public struct ListChainsUseCase: UseCase {

    public struct Options: Sendable {
        public let repoPath: URL

        public init(repoPath: URL) {
            self.repoPath = repoPath
        }
    }

    private let discoveryService: any ChainDiscoveryService

    public init(discoveryService: any ChainDiscoveryService = LocalChainDiscoveryService()) {
        self.discoveryService = discoveryService
    }

    public func run(options: Options) async throws -> [ChainProject] {
        let sources = try discoveryService.discoverSources(repoPath: options.repoPath)
        return try await withThrowingTaskGroup(of: ChainProject.self) { group in
            for source in sources {
                group.addTask {
                    try await source.loadProject()
                }
            }
            var projects: [ChainProject] = []
            for try await project in group {
                projects.append(project)
            }
            return projects.sorted { $0.name < $1.name }
        }
    }
}
