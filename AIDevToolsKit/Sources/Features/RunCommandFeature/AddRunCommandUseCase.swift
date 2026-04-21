import Foundation
import RepositorySDK
import UseCaseSDK

public struct AddRunCommandUseCase: UseCase {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(repoID: UUID, command: RepoRunCommand) throws -> RepositoryConfiguration {
        guard var repo = try store.find(byID: repoID) else {
            throw RunCommandError.repositoryNotFound(repoID)
        }
        var commands = repo.runCommands ?? []
        var cmd = command
        if commands.isEmpty {
            cmd.isDefault = true
        }
        commands.append(cmd)
        repo.runCommands = commands
        try store.update(repo)
        return repo
    }
}
