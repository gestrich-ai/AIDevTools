import AIOutputSDK
import ClaudeChainService
import DataPathsService
import Foundation
import GitSDK
import PipelineService

public struct ExecuteClaudeChainUseCase {

    public struct Options {
        public let githubAccount: String?
        public let project: ChainProject
        public let repoPath: URL
        public let stagingOnly: Bool
        public let taskIndex: Int?
        public let useWorktree: Bool

        public init(
            githubAccount: String?,
            project: ChainProject,
            repoPath: URL,
            stagingOnly: Bool,
            taskIndex: Int? = nil,
            useWorktree: Bool = false
        ) {
            self.githubAccount = githubAccount
            self.project = project
            self.repoPath = repoPath
            self.stagingOnly = stagingOnly
            self.taskIndex = taskIndex
            self.useWorktree = useWorktree
        }
    }

    private let client: any AIClient
    private let dataPathsService: DataPathsService
    private let gitClientFactory: @Sendable (String?) -> GitClient

    public init(
        client: any AIClient,
        dataPathsService: DataPathsService,
        gitClientFactory: @Sendable @escaping (String?) -> GitClient
    ) {
        self.client = client
        self.dataPathsService = dataPathsService
        self.gitClientFactory = gitClientFactory
    }

    public func phases(for project: ChainProject) -> [ChainExecutionPhase] {
        ChainExecutionStrategyFactory.strategy(for: project.kind).initialPhases
    }

    public func run(
        options: Options,
        onProgress: @escaping @Sendable (ChainProgressEvent) -> Void
    ) async throws -> ExecuteSpecChainUseCase.Result {
        let strategy = ChainExecutionStrategyFactory.strategy(for: options.project.kind)
        let worktreeOptions = options.useWorktree
            ? computeChainWorktreeOptions(
                project: options.project,
                repoPath: options.repoPath,
                taskIndex: options.taskIndex
            )
            : nil

        return try await strategy.execute(
            project: options.project,
            repoPath: options.repoPath,
            taskIndex: options.taskIndex,
            stagingOnly: options.stagingOnly,
            worktreeOptions: worktreeOptions,
            client: client,
            git: gitClientFactory(options.githubAccount),
            githubAccount: options.githubAccount,
            onProgress: onProgress
        )
    }

    private func computeChainWorktreeOptions(
        project: ChainProject,
        repoPath: URL,
        taskIndex: Int?
    ) -> WorktreeOptions? {
        let nextTask: ChainTask?
        if let taskIndex {
            nextTask = project.tasks.first(where: { $0.index == taskIndex })
        } else {
            nextTask = project.tasks.first(where: { !$0.isCompleted })
        }

        guard let task = nextTask else { return nil }
        let taskHash = TaskService.generateTaskHash(description: task.description)
        let branchName = PRService.formatBranchName(projectName: project.name, taskHash: taskHash)
        guard let worktreesDir = try? dataPathsService.path(for: .claudeChainWorktrees) else { return nil }

        return WorktreeOptions(
            branchName: branchName,
            destinationPath: worktreesDir.appendingPathComponent(branchName).path,
            repoPath: repoPath.path
        )
    }
}
