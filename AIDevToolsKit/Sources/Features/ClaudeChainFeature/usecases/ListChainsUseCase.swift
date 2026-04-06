import AIOutputSDK
import ClaudeChainService
import Foundation
import GitHubService

public struct ListChainsUseCase {
    private let client: any AIClient
    private let prService: any GitHubPRServiceProtocol
    private let repoPath: URL

    public init(client: any AIClient, repoPath: URL, prService: any GitHubPRServiceProtocol) {
        self.client = client
        self.prService = prService
        self.repoPath = repoPath
    }

    public func stream() -> AsyncThrowingStream<ChainListResult, Error> {
        AsyncThrowingStream { [self] continuation in
            Task {
                let service = ClaudeChainService(client: client, repoPath: repoPath, prService: prService)
                // Swallowing intentionally: cached data is best-effort; a failure here just
                // means no stale results are shown before the fresh fetch completes.
                if let cached = try? await service.listChains(source: .remote, useCache: true),
                   !cached.projects.isEmpty {
                    continuation.yield(cached)
                }
                do {
                    let fresh = try await service.listChains(source: .remote, useCache: false)
                    continuation.yield(fresh)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
