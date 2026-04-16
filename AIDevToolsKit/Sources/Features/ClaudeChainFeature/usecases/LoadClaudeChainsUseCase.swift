import AIOutputSDK
import ClaudeChainService
import DataPathsService
import Foundation
import GitHubService
import PRRadarConfigService

public struct LoadClaudeChainsUseCase {
    private let client: any AIClient
    private let dataPathsService: DataPathsService

    public init(client: any AIClient, dataPathsService: DataPathsService) {
        self.client = client
        self.dataPathsService = dataPathsService
    }

    public func stream(repoPath: URL, githubAccount: String?) async -> AsyncThrowingStream<ChainListResult, Error> {
        let repoSlug = PRDiscoveryService.repoSlug(fromRepoPath: repoPath.path)?
            .replacingOccurrences(of: "/", with: "-") ?? ""
        let prService = try? await makeOptionalPRService(repoPath: repoPath, githubAccount: githubAccount)

        return ListChainsUseCase(
            client: client,
            repoPath: repoPath,
            prService: prService,
            dataPathsService: dataPathsService,
            repoSlug: repoSlug
        ).stream()
    }

    private func makeOptionalPRService(
        repoPath: URL,
        githubAccount: String?
    ) async throws -> (any GitHubPRServiceProtocol)? {
        guard let githubAccount, !githubAccount.isEmpty else { return nil }
        return try await GitHubServiceFactory.createPRService(
            repoPath: repoPath.path,
            githubAccount: githubAccount,
            dataPathsService: dataPathsService
        )
    }
}
