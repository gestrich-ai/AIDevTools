import Foundation
import RepositorySDK
import UseCaseSDK

public struct ConfigureNewRepositoryUseCase: UseCase {
    private let addRepository: AddRepositoryUseCase
    private let repositoryStore: RepositoryStore
    private let updateRepository: UpdateRepositoryUseCase

    public init(
        addRepository: AddRepositoryUseCase,
        repositoryStore: RepositoryStore,
        updateRepository: UpdateRepositoryUseCase
    ) {
        self.addRepository = addRepository
        self.repositoryStore = repositoryStore
        self.updateRepository = updateRepository
    }

    public func run(
        repository: RepositoryConfiguration,
        casesDirectory: String? = nil,
        completedDirectory: String? = nil,
        proposedDirectory: String? = nil
    ) throws -> RepositoryConfiguration {
        let added = try addRepository.run(path: repository.path, name: repository.name)
        var full = repository.with(id: added.id)
        if let casesDirectory {
            full.eval = EvalRepoSettings(casesDirectory: casesDirectory)
        }
        if completedDirectory != nil || proposedDirectory != nil {
            full.planner = MarkdownPlannerRepoSettings(
                proposedDirectory: proposedDirectory,
                completedDirectory: completedDirectory
            )
        }
        try updateRepository.run(full)
        return added
    }
}
