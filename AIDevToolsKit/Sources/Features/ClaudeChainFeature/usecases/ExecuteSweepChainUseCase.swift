import AIOutputSDK
import ClaudeChainService
import CredentialService
import Foundation
import SweepFeature
import UseCaseSDK

public struct ExecuteSweepChainUseCase: UseCase {

    public struct Options: Sendable {
        public let baseBranch: String
        public let githubAccount: String?
        public let project: ChainProject
        public let repoPath: URL

        public init(project: ChainProject, repoPath: URL, githubAccount: String? = nil) {
            self.baseBranch = project.baseBranch
            self.githubAccount = githubAccount
            self.project = project
            self.repoPath = repoPath
        }
    }

    public typealias Progress = RunSweepBatchUseCase.Progress

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> ExecuteSpecChainUseCase.Result {
        if let account = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: account
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                setenv("GH_TOKEN", token, 1)
            }
        }

        let taskDirectory = options.repoPath.appendingPathComponent(options.project.basePath)
        let useCase = RunSweepBatchUseCase(client: client)
        let sweepOptions = RunSweepBatchUseCase.Options(
            taskDirectory: taskDirectory,
            repoPath: options.repoPath,
            baseBranch: options.baseBranch
        )

        let result = try await useCase.run(options: sweepOptions, onProgress: onProgress)
        return ExecuteSpecChainUseCase.Result(
            success: result.success,
            message: result.message,
            prURL: result.prURL
        )
    }
}
