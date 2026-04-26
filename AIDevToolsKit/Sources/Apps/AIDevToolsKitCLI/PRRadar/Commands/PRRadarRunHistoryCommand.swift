import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModelsService

struct PRRadarRunHistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-history",
        abstract: "Show history of past run-all executions"
    )

    @Option(name: .long, help: "Repository name (from config list)")
    var config: String?

    @Option(name: .long, help: "Number of recent runs to show (default: 10)")
    var limit: Int = 10

    @Flag(name: .long, help: "Show per-PR breakdown for each run")
    var detailed: Bool = false

    func run() async throws {
        let prRadarConfig = try resolvePRRadarConfig(repoName: config)
        let runsDir = "\(prRadarConfig.outputDir)/runs"
        let fm = FileManager.default

        guard fm.fileExists(atPath: runsDir) else {
            print("No run history found. Runs are saved to: \(runsDir)")
            return
        }

        let files = try fm.contentsOfDirectory(atPath: runsDir)
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .reversed()
            .prefix(limit)

        if files.isEmpty {
            print("No run history found at \(runsDir)")
            return
        }

        let decoder = JSONDecoder()
        print("Showing \(files.count) run\(files.count == 1 ? "" : "s") from \(prRadarConfig.name)/runs/\n")

        for filename in files {
            let path = "\(runsDir)/\(filename)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let manifest = try? decoder.decode(RunManifest.self, from: data) else {
                continue
            }

            let prReports = manifest.prs.map { entry -> RunAllPRStats in
                let report = loadReportSummary(outputDir: prRadarConfig.outputDir, prNumber: entry.prNumber)
                return RunAllPRStats(
                    aiTasksRun: report?.totalTasksEvaluated ?? 0,
                    entry: entry,
                    totalCostUsd: report?.totalCostUsd ?? 0,
                    totalDurationMs: report?.totalDurationMs ?? 0,
                    violationsFound: report?.violationsFound ?? 0
                )
            }

            let totalTasks = prReports.map(\.aiTasksRun).reduce(0, +)
            let totalViolations = prReports.map(\.violationsFound).reduce(0, +)
            let totalCost = prReports.map(\.totalCostUsd).reduce(0, +)
            let rules = manifest.rulesPathName ?? "default"
            let succeeded = manifest.prs.filter { $0.status == .succeeded }.count
            let failed = manifest.prs.filter { $0.status == .failed }.count

            print("── \(manifest.startedAt)  [\(manifest.config)/\(rules)] ─────────────")
            print("   PRs: \(manifest.prs.count) (\(succeeded) succeeded, \(failed) failed)")
            print("   AI tasks: \(totalTasks)  |  Violations: \(totalViolations)  |  Cost: $\(String(format: "%.4f", totalCost))")

            if detailed && !prReports.isEmpty {
                print("   PR Breakdown (sorted by duration):")
                for pr in prReports.sorted(by: { $0.totalDurationMs > $1.totalDurationMs }) {
                    let icon = pr.entry.status == .succeeded ? "✓" : "✗"
                    let title = String(pr.entry.title.prefix(50))
                    print("     \(icon) #\(pr.entry.prNumber)  \(pr.formattedDuration)  \(pr.aiTasksRun)t  \(pr.violationsFound)v  $\(String(format: "%.4f", pr.totalCostUsd))  \(title)")
                    if let reason = pr.entry.failureReason {
                        print("         ↳ \(reason)")
                    }
                }
            }
            print()
        }
    }

    private func loadReportSummary(outputDir: String, prNumber: Int) -> ReportSummary? {
        let decoder = JSONDecoder()

        // Try commit-scoped path via metadata phase_result.json
        let metadataResultPath = PRRadarPhasePaths.phaseDirectory(
            outputDir: outputDir, prNumber: prNumber, phase: .metadata
        ) + "/\(PRRadarPhasePaths.phaseResultFilename)"

        if let metaData = try? Data(contentsOf: URL(fileURLWithPath: metadataResultPath)),
           let metaResult = try? decoder.decode(PhaseResult.self, from: metaData),
           let commitHash = metaResult.stats?.metadata?["commitHash"] {
            let reportPath = PRRadarPhasePaths.phaseDirectory(
                outputDir: outputDir, prNumber: prNumber, phase: .report, commitHash: commitHash
            ) + "/\(PRRadarPhasePaths.summaryJSONFilename)"
            if let reportData = try? Data(contentsOf: URL(fileURLWithPath: reportPath)),
               let report = try? decoder.decode(ReviewReport.self, from: reportData) {
                return report.summary
            }
        }

        // Fall back: scan analysis/ subdirectories for any report/summary.json
        let analysisDir = "\(outputDir)/\(prNumber)/\(PRRadarPhasePaths.analysisDirectoryName)"
        if let commits = try? FileManager.default.contentsOfDirectory(atPath: analysisDir) {
            for commit in commits.sorted().reversed() {
                let reportPath = "\(analysisDir)/\(commit)/\(PRRadarPhase.report.rawValue)/\(PRRadarPhasePaths.summaryJSONFilename)"
                if let reportData = try? Data(contentsOf: URL(fileURLWithPath: reportPath)),
                   let report = try? decoder.decode(ReviewReport.self, from: reportData) {
                    return report.summary
                }
            }
        }

        return nil
    }
}
