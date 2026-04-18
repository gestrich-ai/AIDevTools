import Foundation
import Logging
import OctokitSDK

private let logger = Logger(label: "GitHubPRLoaderUseCase")

public struct GitHubPRLoaderUseCase {

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

    private let config: GitHubRepoConfig

    public init(config: GitHubRepoConfig) {
        self.config = config
    }

    public func execute(filter: PRFilter) -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.listLoadStarted)

                let service: GitHubPRService
                do {
                    service = try await makeService()
                } catch {
                    logger.error("execute(filter:): service setup failed: \(error)")
                    continuation.yield(.listFetchFailed(error.localizedDescription))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                // Swallowing intentionally: author name cache is best-effort; missing names
                // fall back to login handles, which does not affect PR data correctness.
                let cachedAuthorEntries = (try? await service.loadAllAuthors()) ?? []
                let nameMap = Dictionary(uniqueKeysWithValues: cachedAuthorEntries.map { ($0.login, $0.name) })

                let cachedGHPRs = await service.readAllCachedPRs()
                let cachedPRs: [PRMetadata] = cachedGHPRs
                    .map { $0.withAuthorNames(from: nameMap) }
                    .compactMap { try? $0.toPRMetadata() }
                    .sorted { $0.number > $1.number }
                let filteredCached = cachedPRs.filter { filter.matches($0) }
                continuation.yield(.cached(filteredCached))

                let cachedByNumber: [Int: PRMetadata] = Dictionary(
                    uniqueKeysWithValues: cachedPRs.map { ($0.number, $0) }
                )

                continuation.yield(.listFetchStarted)

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

                // Re-read from cache after the API write: the cache is the source of truth.
                // updatePRs(filter:) already wrote the API results to disk, so reading back
                // from cache and applying filter.matches() gives consistent results — the same
                // logic used for the .cached event above. Never return raw API data directly.
                let postFetchCached = await service.readAllCachedPRs()
                let fetchedPRs = postFetchCached
                    .map { $0.withAuthorNames(from: nameMap) }
                    .compactMap { try? $0.toPRMetadata() }
                    .filter { filter.matches($0) }
                    .sorted { $0.number > $1.number }

                continuation.yield(.fetched(fetchedPRs))

                // Enrichment targets: PRs the API returned that also pass the filter.
                // Using fetchedGHPRs (not the full cache) scopes enrichment to PRs that
                // the API confirmed are still relevant — avoids re-enriching stale entries.
                let enrichmentTargets = fetchedGHPRs
                    .map { $0.withAuthorNames(from: nameMap) }
                    .compactMap { try? $0.toPRMetadata() }
                    .filter { filter.matches($0) }
                    .sorted { $0.number > $1.number }

                var rateLimited = false
                var accessForbidden = false
                for pr in enrichmentTargets {
                    if rateLimited || accessForbidden { break }

                    // If the PR hasn't changed since the last disk-cached version, read enrichment
                    // from disk cache rather than hitting GitHub again. On first load (cache miss)
                    // the service falls through to a live fetch automatically.
                    let isUnchanged = cachedByNumber[pr.number].map { $0.updatedAt == pr.updatedAt } ?? false

                    continuation.yield(.prFetchStarted(prNumber: pr.number))
                    do {
                        let enriched = try await enrichPR(pr, using: service, useCache: isUnchanged)
                        // Swallowing intentionally: author cache is best-effort; a write failure
                        // does not affect the PR data the caller receives.
                        try? await updateAuthorCache(for: enriched)
                        continuation.yield(.prUpdated(enriched))
                    } catch {
                        logger.error("execute(filter:): enrichment failed for PR #\(pr.number): \(error)")
                        if let octokitError = error as? OctokitClientError, case .forbidden = octokitError {
                            accessForbidden = true
                        } else if error.localizedDescription.lowercased().contains("rate limit") {
                            rateLimited = true
                        }
                        continuation.yield(.prFetchFailed(prNumber: pr.number, error: error.localizedDescription))
                    }
                }
                if rateLimited {
                    continuation.yield(.listFetchFailed("GitHub rate limit hit — enrichment stopped. Wait a minute then refresh."))
                } else if accessForbidden {
                    continuation.yield(.listFetchFailed("GitHub access denied — some PRs could not be loaded. Check your permissions."))
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
                    let service = try await makeService()
                    let ghPR = try await service.pullRequest(number: prNumber, useCache: false)
                    let base = try ghPR.toPRMetadata()
                    let enriched = try await enrichPR(base, using: service, useCache: false)
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

    private func updateAuthorCache(for pr: PRMetadata) async throws {
        var logins = Set<String>()
        if !pr.author.login.isEmpty { logins.insert(pr.author.login) }
        if let comments = pr.githubComments {
            comments.comments.compactMap { $0.author?.login }.forEach { logins.insert($0) }
            comments.reviews.compactMap { $0.author?.login }.forEach { logins.insert($0) }
            comments.reviewComments.compactMap { $0.author?.login }.forEach { logins.insert($0) }
        }
        guard !logins.isEmpty else { return }
        _ = try await LoadAuthorsUseCase(config: config).execute(logins: logins)
    }

    private func makeService() async throws -> GitHubPRService {
        let gitHub = try await GitHubServiceFactory.createGitHubAPI(
            repoPath: config.repoPath,
            githubAccount: config.account,
            explicitToken: config.token
        )
        return GitHubPRService(rootURL: config.cacheURL, apiClient: gitHub)
    }

    private func enrichPR(
        _ pr: PRMetadata,
        using service: GitHubPRService,
        useCache: Bool
    ) async throws -> PRMetadata {
        // service.comments() already fetches reviews internally (getPullRequestComments calls
        // listReviews). Calling service.reviews() separately would duplicate that request.
        let comments = try await withStep("comments", pr: pr.number) {
            try await service.comments(number: pr.number, useCache: useCache)
        }
        let checkRuns = try await withStep("checkRuns", pr: pr.number) {
            try await service.checkRuns(number: pr.number, useCache: useCache)
        }
        // isMergeable has no disk cache — skip the live call when reading from cache to avoid
        // an extra API call for PRs whose updatedAt hasn't changed.
        let isMergeable: Bool? = try await useCache ? nil : withStep("isMergeable", pr: pr.number) {
            try await service.isMergeable(number: pr.number)
        }

        var enriched = pr
        enriched.githubComments = comments
        enriched.reviews = comments.reviews
        enriched.checkRuns = checkRuns
        enriched.isMergeable = isMergeable

        return enriched
    }

    private func withStep<T: Sendable>(_ step: String, pr: Int, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            logger.error("enrichPR(#\(pr)): step '\(step)' failed: \(error)")
            throw error
        }
    }
}
