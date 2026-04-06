import Foundation
import GitSDK
import UseCaseSDK

public struct AddWorktreeUseCase: UseCase {
    private let gitClient: GitClient

    public init(gitClient: GitClient) {
        self.gitClient = gitClient
    }

    public func execute(repoPath: String, destination: String, branch: String) async throws {
        do {
            _ = try await gitClient.createWorktree(baseBranch: branch, destination: destination, workingDirectory: repoPath)
        } catch {
            throw WorktreeError.addFailed(error.localizedDescription)
        }
    }
}
