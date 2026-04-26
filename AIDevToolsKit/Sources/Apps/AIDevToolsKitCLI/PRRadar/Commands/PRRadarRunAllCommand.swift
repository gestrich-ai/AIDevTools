import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature
import RepositorySDK

struct PRRadarRunAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-all",
        abstract: "Run the full pipeline for all PRs matching a date and state filter"
    )

    @OptionGroup var filterOptions: PRRadarFilterOptions

    @Option(name: .long, help: "Repository name (from repos list)")
    var config: String?

    @Option(name: .long, help: "Rule path name (uses the default rule path if omitted)")
    var rulesPathName: String?

    @Option(name: .long, help: "Minimum violation score")
    var minScore: String?

    @Option(name: .long, help: "GitHub repo (owner/name)")
    var repo: String?

    @Flag(name: .long, help: "Post comments to GitHub (default: dry-run)")
    var comment: Bool = false

    @Option(name: .long, help: "Maximum number of PRs to process")
    var limit: String?

    @Option(name: .long, help: "Diff source: 'git' (local git history) or 'github-api' (GitHub REST API)")
    var diffSource: DiffSource?

    @Option(name: .long, help: "Analysis mode: regex, script, ai, or all (default: all)")
    var mode: AnalysisMode = .all

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let prRadarConfig = try resolvePRRadarConfig(repoName: config, diffSource: diffSource)
        let prFilter = try filterOptions.buildFilter(config: prRadarConfig)
        guard prFilter.dateFilter != nil else {
            throw ValidationError("A date filter is required. Use --since, --lookback-hours, --updated-since, or --updated-lookback-hours.")
        }

        let useCase = RunAllUseCase(config: prRadarConfig)

        for try await progress in useCase.execute(
            filter: prFilter,
            rulesDir: try resolveRulesDir(rulesPathName: rulesPathName, config: prRadarConfig),
            minScore: minScore,
            repo: repo,
            comment: comment,
            limit: limit,
            analysisMode: mode,
            rulesPathName: rulesPathName
        ) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                print(text, terminator: "")
            case .prepareStreamEvent(let event):
                switch event {
                case .textDelta(let text):
                    if !quiet { printPRRadarAIOutput(text, verbose: verbose) }
                case .toolUse(let name, _):
                    if !quiet && verbose { printPRRadarAIToolUse(name) }
                default:
                    break
                }
            case .taskEvent(_, let event):
                switch event {
                case .streamEvent(let event):
                    switch event {
                    case .textDelta(let text):
                        if !quiet { printPRRadarAIOutput(text, verbose: verbose) }
                    case .toolUse(let name, _):
                        if !quiet && verbose { printPRRadarAIToolUse(name) }
                    default:
                        break
                    }
                case .prompt, .completed:
                    break
                }
            case .completed(let output):
                printRunSummary(output)
            case .failed(let error, let logs):
                if !logs.isEmpty { printPRRadarError(logs) }
                throw PRRadarCLIError.phaseFailed("run-all failed: \(error)")
            }
        }
    }

    private func printRunSummary(_ output: RunAllOutput) {
        let manifest = output.manifest
        let stats = output.prStats
        let rules = manifest.rulesPathName ?? "default"

        let totalTasks = stats.map(\.aiTasksRun).reduce(0, +)
        let totalViolations = stats.map(\.violationsFound).reduce(0, +)
        let totalCost = stats.map(\.totalCostUsd).reduce(0, +)

        print("\n── Run Summary ─────────────────────────────────────────────────────")
        print("Config: \(manifest.config)/\(rules)  |  \(output.analyzedCount) succeeded, \(output.failedCount) failed")
        print("Total:  \(totalTasks) AI tasks  |  \(totalViolations) violations  |  $\(String(format: "%.4f", totalCost))")

        if !stats.isEmpty {
            print("\nPR Breakdown (sorted by duration):")
            for pr in stats.sorted(by: { $0.totalDurationMs > $1.totalDurationMs }) {
                let icon = pr.entry.status == .succeeded ? "✓" : "✗"
                let title = String(pr.entry.title.prefix(48))
                let tasks = "\(pr.aiTasksRun) task\(pr.aiTasksRun == 1 ? "" : "s")"
                let violations = "\(pr.violationsFound) violation\(pr.violationsFound == 1 ? "" : "s")"
                print("  \(icon) #\(pr.entry.prNumber)  \(pr.formattedDuration)  \(tasks)  \(violations)  $\(String(format: "%.4f", pr.totalCostUsd))  \(title)")
                if let reason = pr.entry.failureReason {
                    print("      ↳ \(reason)")
                }
            }
        }
        print("────────────────────────────────────────────────────────────────────")
    }
}
