import CredentialService
import Foundation
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct RunAllUseCase: StreamingUseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(
        filter: PRFilter,
        rulesDir: String,
        minScore: String? = nil,
        comment: Bool = false,
        limit: String? = nil,
        analysisMode: AnalysisMode = .all,
        rulesPathName: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<RunAllOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    guard let githubAccount = config.githubCredentialProfileId else {
                        throw CredentialError.notConfigured(profileId: nil)
                    }
                    let gitHub = try await GitHubServiceFactory.createGitHubAPI(repoPath: config.repoPath, githubAccount: githubAccount, explicitToken: config.explicitToken)

                    let limitNum = Int(limit ?? "10000") ?? 10000
                    let dateLabel = filter.dateFilter.map { "Fetching PRs \($0.fieldLabel) since \($0.date)" } ?? "Fetching all PRs"
                    let stateLabel = filter.state?.displayName ?? "all"
                    continuation.yield(.log(text: "\(dateLabel) (state: \(stateLabel))...\n"))

                    let prs = try await gitHub.listPullRequests(
                        limit: limitNum,
                        filter: filter
                    )

                    continuation.yield(.log(text: "Found \(prs.count) PRs to analyze\n"))

                    var analyzedCount = 0
                    var failedCount = 0
                    let totalCount = prs.count
                    let runStartedAt = ISO8601DateFormatter().string(from: Date())
                    var manifestEntries: [PRManifestEntry] = []
                    var prStats: [RunAllPREntry] = []

                    for (index, pr) in prs.enumerated() {
                        let prNumber = pr.number
                        let current = index + 1
                        continuation.yield(.progress(current: current, total: totalCount))
                        continuation.yield(.log(text: "\n[\(current)/\(totalCount)] PR #\(prNumber): \(pr.title)\n"))

                        let analyzeUseCase = RunPipelineUseCase(config: config)
                        var succeeded = false
                        var pipelineOutput: RunPipelineOutput?
                        var failureReason: String?

                        for try await progress in analyzeUseCase.execute(
                            prNumber: prNumber,
                            rulesDir: rulesDir,
                            noDryRun: comment,
                            minScore: minScore,
                            analysisMode: analysisMode
                        ) {
                            switch progress {
                            case .running: break
                            case .progress: break
                            case .log(let text):
                                continuation.yield(.log(text: text))
                            case .prepareStreamEvent(let event):
                                continuation.yield(.prepareStreamEvent(event))
                            case .taskEvent(let task, let event):
                                continuation.yield(.taskEvent(task: task, event: event))
                            case .completed(let output):
                                succeeded = true
                                pipelineOutput = output
                            case .failed(let error, _):
                                continuation.yield(.log(text: "  Failed: \(error)\n"))
                                failureReason = error
                            }
                        }

                        let summary = pipelineOutput?.report?.report.summary
                        let entry = PRManifestEntry(
                            costUsd: summary?.totalCostUsd,
                            failureReason: failureReason,
                            prNumber: prNumber,
                            status: succeeded ? .succeeded : .failed,
                            title: pr.title,
                            violationsFound: summary?.violationsFound
                        )
                        manifestEntries.append(entry)

                        prStats.append(RunAllPREntry(entry: entry, summary: summary))

                        if succeeded {
                            analyzedCount += 1
                        } else {
                            failedCount += 1
                        }
                    }

                    let manifest = RunManifest(
                        completedAt: ISO8601DateFormatter().string(from: Date()),
                        config: config.name,
                        prs: manifestEntries,
                        rulesPathName: rulesPathName,
                        startedAt: runStartedAt
                    )
                    do {
                        try Self.saveManifest(manifest, outputDir: config.resolvedOutputDir)
                    } catch {
                        continuation.yield(.log(text: "Warning: failed to save run manifest: \(error.localizedDescription)\n"))
                    }

                    continuation.yield(.log(text: "\nRun complete: \(analyzedCount) succeeded, \(failedCount) failed\n"))

                    let output = RunAllOutput(analyzedCount: analyzedCount, failedCount: failedCount, manifest: manifest, prStats: prStats)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    private static func saveManifest(_ manifest: RunManifest, outputDir: String) throws {
        let runsDir = "\(outputDir)/runs"
        try FileManager.default.createDirectory(atPath: runsDir, withIntermediateDirectories: true)
        let label = manifest.rulesPathName ?? "default"
        let datePart = manifest.startedAt
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: URL(fileURLWithPath: "\(runsDir)/\(datePart)-\(label).json"))
    }
}

// MARK: - Supporting Types

public struct RunAllOutput: Sendable {
    public let analyzedCount: Int
    public let failedCount: Int
    public let manifest: RunManifest
    public let prStats: [RunAllPREntry]

    public init(analyzedCount: Int, failedCount: Int, manifest: RunManifest, prStats: [RunAllPREntry]) {
        self.analyzedCount = analyzedCount
        self.failedCount = failedCount
        self.manifest = manifest
        self.prStats = prStats
    }
}
