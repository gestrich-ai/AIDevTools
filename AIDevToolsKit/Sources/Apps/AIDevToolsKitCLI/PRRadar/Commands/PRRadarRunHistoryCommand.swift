import ArgumentParser
import Foundation
import PRRadarCLIService
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
        let runsDir = "\(prRadarConfig.resolvedOutputDir)/runs"

        guard FileManager.default.fileExists(atPath: runsDir) else {
            print("No run history found. Runs are saved to: \(runsDir)")
            return
        }

        let runs = try RunHistoryService.loadRuns(outputDir: prRadarConfig.resolvedOutputDir, limit: limit)

        if runs.isEmpty {
            print("No run history found at \(runsDir)")
            return
        }

        print("Showing \(runs.count) run\(runs.count == 1 ? "" : "s") from \(prRadarConfig.name)/runs/\n")

        for historyEntry in runs {
            let manifest = historyEntry.manifest
            let prEntries = historyEntry.prEntries

            let totalTasks = prEntries.compactMap(\.summary).map(\.totalTasksEvaluated).reduce(0, +)
            let totalViolations = prEntries.compactMap(\.summary).map(\.violationsFound).reduce(0, +)
            let totalCost = prEntries.compactMap(\.summary).map(\.totalCostUsd).reduce(0, +)
            let rules = manifest.rulesPathName ?? "default"
            let succeeded = manifest.prs.filter { $0.status == .succeeded }.count
            let failed = manifest.prs.filter { $0.status == .failed }.count

            print("── \(manifest.startedAt)  [\(manifest.config)/\(rules)] ─────────────")
            print("   PRs: \(manifest.prs.count) (\(succeeded) succeeded, \(failed) failed)")
            print("   AI tasks: \(totalTasks)  |  Violations: \(totalViolations)  |  Cost: $\(String(format: "%.4f", totalCost))")

            if detailed && !prEntries.isEmpty {
                print("   PR Breakdown (sorted by duration):")
                for pr in prEntries.sorted(by: { ($0.summary?.totalDurationMs ?? 0) > ($1.summary?.totalDurationMs ?? 0) }) {
                    let icon = pr.entry.status == .succeeded ? "✓" : "✗"
                    let title = String(pr.entry.title.prefix(50))
                    let tasks = pr.summary?.totalTasksEvaluated ?? 0
                    let violations = pr.summary?.violationsFound ?? 0
                    let cost = pr.summary?.totalCostUsd ?? 0
                    let duration = pr.summary?.formattedDuration ?? "–"
                    print("     \(icon) #\(pr.entry.prNumber)  \(duration)  \(tasks)t  \(violations)v  $\(String(format: "%.4f", cost))  \(title)")
                    if let reason = pr.entry.failureReason {
                        print("         ↳ \(reason)")
                    }
                }
            }
            print()
        }
    }
}
