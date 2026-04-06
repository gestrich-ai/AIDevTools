import Foundation
import GitSDK
import UseCaseSDK

public struct RemoveWorktreeUseCase: UseCase {
    private let gitClient: GitClient

    public init(gitClient: GitClient) {
        self.gitClient = gitClient
    }

    public func execute(repoPath: String, worktreePath: String, force: Bool = false) async throws {
        do {
            _ = try await gitClient.removeWorktree(worktreePath: worktreePath, force: force, workingDirectory: repoPath)
        } catch {
            throw WorktreeError.removeFailed(error.localizedDescription)
        }
    }
}
