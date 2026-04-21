import Foundation
import RepositorySDK
import UseCaseSDK

public struct RemoveRunCommandUseCase: UseCase {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(repoID: UUID, commandID: UUID) throws -> RepositoryConfiguration {
        guard var repo = try store.find(byID: repoID) else {
            throw RunCommandError.repositoryNotFound(repoID)
        }
        guard repo.runCommands?.contains(where: { $0.id == commandID }) == true else {
            throw RunCommandError.commandNotFound(commandID)
        }
        repo.runCommands?.removeAll { $0.id == commandID }
        if repo.runCommands?.isEmpty == true {
            repo.runCommands = nil
        }
        try store.update(repo)
        return repo
    }
}
