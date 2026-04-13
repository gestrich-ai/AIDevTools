import ClaudeChainService
import Foundation
import GitHubService
import Logging
import PRRadarModelsService
import UseCaseSDK

private let logger = Logger(label: "GetChainDetailUseCase")

public struct GetChainDetailUseCase: UseCase, StreamingUseCase {

    public struct Options: Sendable {
        public let project: ChainProject

        public init(project: ChainProject) {
            self.project = project
        }
    }

    private let config: GitHubRepoConfig
    private let gitHubPRService: any GitHubPRServiceProtocol

    public init(gitHubPRService: any GitHubPRServiceProtocol, config: GitHubRepoConfig) {
        self.config = config
        self.gitHubPRService = gitHubPRService
    }

    // MARK: - Cache-first then network stream

    /// Yields cached data immediately (if available), then yields progressively enriched data from the network.
    public func stream(options: Options) -> AsyncThrowingStream<ChainProjectDetail, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if let cached = try? await loadCached(options: options) {
                    continuation.yield(cached)
                }
                do {
                    try await streamLive(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - UseCase conformance

    public func run(options: Options) async throws -> ChainProjectDetail {
        var lastDetail: ChainProjectDetail?
        for try await detail in stream(options: options) {
            lastDetail = detail
        }
        guard let detail = lastDetail else {
            throw GetChainDetailError(project: options.project.name)
        }
        return detail
    }

    // MARK: - Cache-first load (no network)

    private func loadCached(options: Options) async throws -> ChainProjectDetail? {
        let project = options.project
        guard let prNumbers = try await gitHubPRService.readCachedIndex(key: project.cacheIndexKey) else {
            return nil
        }

        var enrichedPRsByHash: [String: EnrichedPR] = [:]
        for number in prNumbers {
            // Swallowing intentionally: cache reads are best-effort; missing or malformed PRs are skipped.
            guard let pr = try? await gitHubPRService.pullRequest(number: number, useCache: true),
                  let metadata = try? pr.toPRMetadata() else { continue }
            let enrichedPR = EnrichedPR(
                pr: metadata,
                reviewStatus: PRReviewStatus(approvedBy: [], pendingReviewers: []),
                buildStatus: .unknown
            )
            if let hash = project.taskHash(for: metadata) {
                enrichedPRsByHash[hash] = enrichedPR
            }
        }

        let enrichedTasks = project.tasks.map { task in
            EnrichedChainTask(task: task, enrichedPR: enrichedPRsByHash[generateTaskHash(task.description)])
        }
        return ChainProjectDetail(project: project, enrichedTasks: enrichedTasks)
    }

    // MARK: - Live streaming via GitHubPRLoaderUseCase

    private func streamLive(
        options: Options,
        continuation: AsyncThrowingStream<ChainProjectDetail, Error>.Continuation
    ) async throws {
        let project = options.project
        let loader = GitHubPRLoaderUseCase(config: config)
        let filter = PRFilter(headRefNamePrefix: project.branchPrefix, state: .open)

        var openEnrichedByHash: [String: EnrichedPR] = [:]
        var fetchedOpenPRNumbers: [Int] = []

        for await event in loader.execute(filter: filter) {
            switch event {
            case .listLoadStarted, .listFetchStarted, .prFetchStarted:
                break
            case .cached(let prs):
                guard !prs.isEmpty else { break }
                for metadata in prs {
                    let enrichedPR = EnrichedPR(
                        pr: metadata,
                        reviewStatus: PRReviewStatus(reviews: metadata.reviews ?? []),
                        buildStatus: PRBuildStatus.from(checkRuns: metadata.checkRuns ?? [], isMergeable: metadata.isMergeable)
                    )
                    if let hash = project.taskHash(for: metadata) {
                        openEnrichedByHash[hash] = enrichedPR
                    }
                }
                let cachedTasks = project.tasks.map { task in
                    EnrichedChainTask(task: task, enrichedPR: openEnrichedByHash[generateTaskHash(task.description)])
                }
                continuation.yield(ChainProjectDetail(project: project, enrichedTasks: cachedTasks))
            case .fetched(let prs):
                fetchedOpenPRNumbers = prs.map { $0.number }
                var newPRsByHash: [String: EnrichedPR] = [:]
                for metadata in prs {
                    let enrichedPR = EnrichedPR(
                        pr: metadata,
                        reviewStatus: PRReviewStatus(approvedBy: [], pendingReviewers: []),
                        buildStatus: .unknown
                    )
                    if let hash = project.taskHash(for: metadata) {
                        newPRsByHash[hash] = enrichedPR
                    }
                }
                openEnrichedByHash = newPRsByHash
                let fetchedTasks = project.tasks.map { task in
                    EnrichedChainTask(task: task, enrichedPR: openEnrichedByHash[generateTaskHash(task.description)])
                }
                continuation.yield(ChainProjectDetail(project: project, enrichedTasks: fetchedTasks))
            case .prUpdated(let metadata):
                let enrichedPR = EnrichedPR(
                    pr: metadata,
                    reviewStatus: PRReviewStatus(reviews: metadata.reviews ?? []),
                    buildStatus: PRBuildStatus.from(checkRuns: metadata.checkRuns ?? [], isMergeable: metadata.isMergeable)
                )
                if let hash = project.taskHash(for: metadata) {
                    openEnrichedByHash[hash] = enrichedPR
                }
                let updatedTasks = project.tasks.map { task in
                    EnrichedChainTask(task: task, enrichedPR: openEnrichedByHash[generateTaskHash(task.description)])
                }
                continuation.yield(ChainProjectDetail(project: project, enrichedTasks: updatedTasks))
            case .prFetchFailed(let prNumber, let error):
                logger.error("streamLive: enrichment failed for PR #\(prNumber): \(error)")
            case .listFetchFailed(let message):
                logger.error("streamLive: list fetch failed: \(message)")
                continuation.finish(throwing: GitHubPRServiceError.listFetchFailed(message))
                return
            case .completed:
                break
            }
        }

        // Fetch merged PRs using the existing list approach — no enrichment needed
        let allMerged = try await gitHubPRService.listPullRequests(limit: 500, filter: PRFilter(state: .merged))
        let mergedPRs = allMerged.filter { ($0.headRefName ?? "").hasPrefix(project.branchPrefix) }

        let matchedHashes = Set(openEnrichedByHash.keys)
        let mergedPRsToFetch = mergedPRs.filter { pr in
            guard let headRefName = pr.headRefName else { return false }
            if let branchInfo = BranchInfo.fromBranchName(headRefName) {
                return !matchedHashes.contains(branchInfo.taskHash)
            }
            // Sweep branches use timestamps, not hashes — always fetch and let register() match via PR body
            return true
        }

        var mergedPRDataByNumber: [Int: PRRadarModelsService.GitHubPullRequest] = [:]
        try await withThrowingTaskGroup(of: PRRadarModelsService.GitHubPullRequest.self) { group in
            for number in mergedPRsToFetch.map({ $0.number }) {
                group.addTask {
                    try await gitHubPRService.pullRequest(number: number, useCache: true)
                }
            }
            for try await pr in group {
                mergedPRDataByNumber[pr.number] = pr
            }
        }

        var mergedEnrichedByHash = openEnrichedByHash
        for (_, pr) in mergedPRDataByNumber {
            // Swallowing intentionally: merged PRs missing required fields are skipped and won't appear in the task list.
            guard let metadata = try? pr.toPRMetadata() else { continue }
            let enrichedPR = EnrichedPR(
                pr: metadata,
                reviewStatus: PRReviewStatus(approvedBy: [], pendingReviewers: []),
                buildStatus: .unknown
            )
            if let hash = project.taskHash(for: metadata) {
                mergedEnrichedByHash[hash] = enrichedPR
            }
        }

        let finalEnrichedTasks = project.tasks.map { task in
            EnrichedChainTask(task: task, enrichedPR: mergedEnrichedByHash[generateTaskHash(task.description)])
        }

        // Save PR number index so the next launch can load from cache instantly.
        // Swallowing intentionally: cache writes are best-effort; a failure here doesn't affect correctness.
        let allPRNumbers = fetchedOpenPRNumbers + mergedPRs.map { $0.number }
        try? await gitHubPRService.writeCachedIndex(allPRNumbers, key: project.cacheIndexKey)

        continuation.yield(ChainProjectDetail(project: project, enrichedTasks: finalEnrichedTasks))
        continuation.finish()
    }
}

private struct GetChainDetailError: Error, LocalizedError {
    let project: String
    var errorDescription: String? { "No data available for chain project '\(project)'" }
}
