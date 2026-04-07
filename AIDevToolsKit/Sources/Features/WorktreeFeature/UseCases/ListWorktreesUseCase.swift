import Foundation
import GitSDK
import UseCaseSDK

public struct ListWorktreesUseCase: UseCase {
    private let gitClient: GitClient

    public init(gitClient: GitClient) {
        self.gitClient = gitClient
    }

    public func execute(repoPath: String) async throws -> [WorktreeStatus] {
        let worktrees: [WorktreeInfo]
        do {
            worktrees = try await gitClient.listWorktrees(workingDirectory: repoPath)
        } catch {
            throw WorktreeError.listFailed(error.localizedDescription)
        }
        var statuses: [WorktreeStatus] = []
        for info in worktrees {
            do {
                let isClean = try await gitClient.isWorkingDirectoryClean(workingDirectory: info.path)
                statuses.append(WorktreeStatus(info: info, hasUncommittedChanges: !isClean))
            } catch {
                throw WorktreeError.listFailed(error.localizedDescription)
            }
        }
        return statuses
    }
}
