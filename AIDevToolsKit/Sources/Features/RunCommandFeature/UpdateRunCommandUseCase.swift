import Foundation
import RepositorySDK
import UseCaseSDK

public struct UpdateRunCommandUseCase: UseCase {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(repoID: UUID, command: RepoRunCommand) throws -> RepositoryConfiguration {
        guard var repo = try store.find(byID: repoID) else {
            throw RunCommandError.repositoryNotFound(repoID)
        }
        guard let index = repo.runCommands?.firstIndex(where: { $0.id == command.id }) else {
            throw RunCommandError.commandNotFound(command.id)
        }
        repo.runCommands?[index] = command
        try store.update(repo)
        return repo
    }
}
