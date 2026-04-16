import AIOutputSDK
import ClaudeChainService
import Foundation
import PipelineSDK

public struct PrepareFinalizeStagedChainUseCase {

    public struct Options {
        public let githubAccount: String?
        public let project: ChainProject
        public let repoPath: URL
        public let taskIndex: Int

        public init(
            githubAccount: String?,
            project: ChainProject,
            repoPath: URL,
            taskIndex: Int
        ) {
            self.githubAccount = githubAccount
            self.project = project
            self.repoPath = repoPath
            self.taskIndex = taskIndex
        }
    }

    public struct Result {
        public let blueprint: PipelineBlueprint
        public let task: ChainTask

        public init(blueprint: PipelineBlueprint, task: ChainTask) {
            self.blueprint = blueprint
            self.task = task
        }
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(options: Options) async throws -> Result {
        guard let task = options.project.tasks.first(where: { $0.index == options.taskIndex }) else {
            throw PrepareFinalizeStagedChainError.taskNotFound(index: options.taskIndex, projectName: options.project.name)
        }

        let taskHash = TaskService.generateTaskHash(description: task.description)
        let branchName = PRService.formatBranchName(projectName: options.project.name, taskHash: taskHash)
        let chainOptions = ChainRunOptions(
            baseBranch: options.project.baseBranch,
            branchName: branchName,
            githubAccount: options.githubAccount,
            projectName: options.project.name,
            repoPath: options.repoPath
        )
        let blueprint = try await BuildFinalizePipelineUseCase(client: client).run(task: task, options: chainOptions)
        return Result(blueprint: blueprint, task: task)
    }
}

private enum PrepareFinalizeStagedChainError: LocalizedError {
    case taskNotFound(index: Int, projectName: String)

    var errorDescription: String? {
        switch self {
        case .taskNotFound(let index, let projectName):
            return "Task \(index) not found for chain project '\(projectName)'"
        }
    }
}
