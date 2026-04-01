import Foundation
import RepositorySDK
import UseCaseSDK

public struct RemoveRepositoryWithSettingsUseCase: UseCase {
    private let removeRepository: RemoveRepositoryUseCase

    public init(removeRepository: RemoveRepositoryUseCase) {
        self.removeRepository = removeRepository
    }

    public func run(id: UUID) throws {
        try removeRepository.run(id: id)
    }
}
