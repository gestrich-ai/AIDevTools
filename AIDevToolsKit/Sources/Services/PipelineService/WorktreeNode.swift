import GitSDK
import PipelineSDK

public struct WorktreeNode: PipelineNode {
    public static let worktreePathKey = PipelineContextKey<String>("WorktreeNode.worktreePath")

    public let id: String = "worktree-node"
    public let displayName: String = "Creating worktree"

    private let gitClient: GitClient
    private let options: WorktreeOptions

    public init(options: WorktreeOptions, gitClient: GitClient) {
        self.gitClient = gitClient
        self.options = options
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        onProgress(.output("Creating worktree at \(options.destinationPath)..."))
        try await gitClient.createWorktree(
            baseBranch: options.branchName,
            destination: options.destinationPath,
            workingDirectory: options.repoPath
        )
        var updated = context
        updated[PipelineContext.workingDirectoryKey] = options.destinationPath
        updated[WorktreeNode.worktreePathKey] = options.destinationPath
        return updated
    }
}
