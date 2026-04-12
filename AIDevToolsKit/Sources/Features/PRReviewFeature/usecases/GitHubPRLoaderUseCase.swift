import CredentialService
import Foundation
import GitHubService
import Logging
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

private let logger = Logger(label: "GitHubPRLoaderUseCase")

public struct GitHubPRLoaderUseCase: StreamingUseCase {

    public enum Event: Sendable {
        // List-level events
        case listLoadStarted
        case cached([PRMetadata])
        case listFetchStarted
        case fetched([PRMetadata])
        case listFetchFailed(String)

        // Per-PR events
        case prFetchStarted(prNumber: Int)
        case prUpdated(PRMetadata)
        case prFetchFailed(prNumber: Int, error: String)

        // Terminal
        case completed
    }

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(filter: PRFilter) -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.listLoadStarted)

                let cachedPRs = await PRDiscoveryService.discoverPRs(config: config)
                let filteredCached = cachedPRs.filter { filter.matches($0) }.sorted { $0.number > $1.number }
                continuation.yield(.cached(filteredCached))

                let cachedByNumber: [Int: PRMetadata] = Dictionary(
                    uniqueKeysWithValues: cachedPRs.map { ($0.number, $0) }
                )

                continuation.yield(.listFetchStarted)

                let service: GitHubPRService
                let authorCache: AuthorCacheService
                do {
                    (service, authorCache) = try await makeService()
                } catch {
                    logger.error("execute(filter:): service setup failed: \(error)")
                    continuation.yield(.listFetchFailed(error.localizedDescription))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                let fetchedGHPRs: [GitHubPullRequest]
                do {
                    fetchedGHPRs = try await service.updatePRs(filter: filter)
                } catch {
                    logger.error("execute(filter:): list fetch failed: \(error)")
                    continuation.yield(.listFetchFailed(error.localizedDescription))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                // Swallowing intentionally: a PR that fails to parse is omitted from the list
                // rather than aborting the entire fetch.
                let fetchedPRs = fetchedGHPRs
                    .compactMap { try? $0.toPRMetadata() }
                    .filter { filter.matches($0) }
                    .sorted { $0.number > $1.number }

                continuation.yield(.fetched(fetchedPRs))

                var rateLimited = false
                for pr in fetchedPRs {
                    if rateLimited { break }

                    // If the PR hasn't changed since the last disk-cached version, read enrichment
                    // from disk cache rather than hitting GitHub again. On first load (cache miss)
                    // the service falls through to a live fetch automatically.
                    let isUnchanged = cachedByNumber[pr.number].map { $0.updatedAt == pr.updatedAt } ?? false

                    continuation.yield(.prFetchStarted(prNumber: pr.number))
                    do {
                        let enriched = try await enrichPR(pr, using: service, authorCache: authorCache, useCache: isUnchanged)
                        continuation.yield(.prUpdated(enriched))
                    } catch {
                        let msg = error.localizedDescription
                        logger.error("execute(filter:): enrichment failed for PR #\(pr.number): \(error)")
                        if msg.lowercased().contains("rate limit") || msg.lowercased().contains("access forbidden") {
                            rateLimited = true
                        }
                        continuation.yield(.prFetchFailed(prNumber: pr.number, error: msg))
                    }
                }
                if rateLimited {
                    continuation.yield(.listFetchFailed("GitHub rate limit hit — enrichment stopped. Wait a minute then refresh."))
                }

                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    public func execute(prNumber: Int) -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.prFetchStarted(prNumber: prNumber))

                do {
                    let (service, authorCache) = try await makeService()
                    let ghPR = try await service.pullRequest(number: prNumber, useCache: false)
                    let base = try ghPR.toPRMetadata()
                    let enriched = try await enrichPR(base, using: service, authorCache: authorCache, useCache: false)
                    continuation.yield(.prUpdated(enriched))
                } catch {
                    logger.error("execute(prNumber:): failed for PR #\(prNumber): \(error)")
                    continuation.yield(.prFetchFailed(prNumber: prNumber, error: error.localizedDescription))
                }

                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    private func makeService() async throws -> (GitHubPRService, AuthorCacheService) {
        let cacheURL = try config.requireGitHubCacheURL()
        guard let account = config.githubAccount, !account.isEmpty else {
            throw CredentialError.notConfigured(account: config.name)
        }
        let gitHub = try await GitHubServiceFactory.createGitHubAPI(
            repoPath: config.repoPath,
            githubAccount: account,
            explicitToken: config.explicitToken
        )
        return (GitHubPRService(rootURL: cacheURL, apiClient: gitHub), AuthorCacheService(rootURL: cacheURL))
    }

    private func enrichPR(
        _ pr: PRMetadata,
        using service: GitHubPRService,
        authorCache: AuthorCacheService,
        useCache: Bool
    ) async throws -> PRMetadata {
        // service.comments() already fetches reviews internally (getPullRequestComments calls
        // listReviews). Calling service.reviews() separately would duplicate that request.
        let comments = try await service.comments(number: pr.number, useCache: useCache)
        let checkRuns = try await service.checkRuns(number: pr.number, useCache: useCache)
        // isMergeable has no disk cache — skip the live call when reading from cache to avoid
        // an extra API call for PRs whose updatedAt hasn't changed.
        let isMergeable: Bool? = useCache ? nil : (try await service.isMergeable(number: pr.number))

        var enriched = pr
        enriched.githubComments = comments
        enriched.reviews = comments.reviews
        enriched.checkRuns = checkRuns
        enriched.isMergeable = isMergeable

        // Populate per-repo author cache from data already fetched — no extra API calls.
        updateAuthorCache(authorCache, from: enriched)

        return enriched
    }

    private func updateAuthorCache(_ cache: AuthorCacheService, from pr: PRMetadata) {
        var authors: [(login: String, name: String?, avatarURL: String?)] = []
        authors.append((pr.author.login, pr.author.name, pr.author.avatarURL))
        if let reviews = pr.reviews {
            for review in reviews {
                if let author = review.author {
                    authors.append((author.login, author.name, author.avatarURL))
                }
            }
        }
        for author in authors where !author.login.isEmpty {
            try? cache.update(login: author.login, name: author.name ?? author.login, avatarURL: author.avatarURL)
        }
    }
}
