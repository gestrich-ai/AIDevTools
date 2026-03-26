import ClaudeCLISDK
import Foundation
import RepositorySDK

extension GeneratePlanUseCase {
    public init(
        resolveProposedDirectory: @escaping @Sendable (RepositoryInfo) throws -> URL
    ) {
        self.init(
            client: ClaudeCLIClient(),
            resolveProposedDirectory: resolveProposedDirectory
        )
    }
}
