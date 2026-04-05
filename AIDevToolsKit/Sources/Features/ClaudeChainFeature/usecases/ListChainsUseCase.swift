import ClaudeChainService
import UseCaseSDK

public struct ListChainsUseCase: UseCase {

    private let source: any ChainProjectSource

    public init(source: any ChainProjectSource) {
        self.source = source
    }

    public func run() async throws -> ChainListResult {
        try await source.listChains()
    }
}
