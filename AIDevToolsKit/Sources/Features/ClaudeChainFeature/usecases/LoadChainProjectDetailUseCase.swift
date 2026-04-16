import ClaudeChainService
import CredentialService
import DataPathsService
import Foundation
import GitHubService

public struct LoadChainProjectDetailUseCase {
    private let dataPathsService: DataPathsService

    public init(dataPathsService: DataPathsService) {
        self.dataPathsService = dataPathsService
    }

    public func stream(
        project: ChainProject,
        repoPath: URL,
        githubAccount: String?
    ) async throws -> AsyncThrowingStream<ChainProjectDetail, Error> {
        guard let githubAccount, !githubAccount.isEmpty else {
            throw CredentialError.notConfigured(profileId: githubAccount)
        }

        let service = try await GitHubServiceFactory.createPRService(
            repoPath: repoPath.path,
            githubAccount: githubAccount,
            dataPathsService: dataPathsService
        )
        let config = try await GitHubServiceFactory.makeRepoConfig(
            repoPath: repoPath.path,
            githubAccount: githubAccount,
            dataPathsService: dataPathsService
        )
        return GetChainDetailUseCase(gitHubPRService: service, config: config).stream(options: .init(project: project))
    }
}
