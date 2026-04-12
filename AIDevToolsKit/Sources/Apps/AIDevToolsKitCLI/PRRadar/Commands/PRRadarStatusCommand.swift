import ArgumentParser
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature

struct PRRadarStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show pipeline status for a PR"
    )

    @OptionGroup var options: PRRadarCLIOptions

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)

        async let detailTask = LoadPRDetailUseCase(config: config).execute(prNumber: options.prNumber, commitHash: options.commit)
        async let reviewsTask = PRDiscoveryService.loadReviews(config: config, prNumber: options.prNumber)
        async let checkRunsTask = PRDiscoveryService.loadCheckRuns(config: config, prNumber: options.prNumber)

        let detail = await detailTask
        let reviews = await reviewsTask
        let checkRuns = await checkRunsTask

        struct DisplayStatus {
            let phase: PRRadarPhase
            let status: String
            let fileCount: Int
        }

        var statuses: [DisplayStatus] = []
        for phase in PRRadarPhase.allCases {
            let phaseStatus = detail.phaseStatuses[phase]!
            let statusText: String
            if !phaseStatus.exists {
                statusText = "not started"
            } else if phaseStatus.isComplete {
                statusText = "complete"
            } else if phaseStatus.isPartial {
                statusText = "partial"
            } else {
                statusText = "failed"
            }
            statuses.append(DisplayStatus(
                phase: phase,
                status: statusText,
                fileCount: phaseStatus.completedCount
            ))
        }

        if options.json {
            var jsonOutput: [String: Any] = [:]
            if let commitHash = detail.commitHash { jsonOutput["commitHash"] = commitHash }
            if let baseRefName = detail.baseRefName { jsonOutput["baseRefName"] = baseRefName }
            jsonOutput["availableCommits"] = detail.availableCommits
            var phases: [[String: Any]] = []
            for s in statuses {
                phases.append([
                    "phase": s.phase.rawValue,
                    "status": s.status,
                    "artifacts": s.fileCount,
                ])
            }
            jsonOutput["phases"] = phases
            if let reviews {
                jsonOutput["reviews"] = reviews.map { r in
                    ["login": r.author?.login ?? "", "state": r.state.rawValue] as [String: Any]
                }
            }
            if let checkRuns {
                jsonOutput["checkRuns"] = checkRuns.map { c in
                    var entry: [String: Any] = ["name": c.name, "status": c.status.rawValue]
                    if let conclusion = c.conclusion { entry["conclusion"] = conclusion.rawValue }
                    return entry
                }
            }
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            let branchSuffix = detail.baseRefName.map { " → \($0)" } ?? ""
            if let commitHash = detail.commitHash {
                print("Pipeline status for PR #\(options.prNumber)\(branchSuffix) @ \(commitHash):")
            } else {
                print("Pipeline status for PR #\(options.prNumber)\(branchSuffix):")
            }
            print("")
            print("  \("Phase".padding(toLength: 30, withPad: " ", startingAt: 0))  \("Status".padding(toLength: 12, withPad: " ", startingAt: 0))  Artifacts")
            print("  \("-----".padding(toLength: 30, withPad: " ", startingAt: 0))  \("------".padding(toLength: 12, withPad: " ", startingAt: 0))  ---------")
            for s in statuses {
                let statusIcon: String
                switch s.status {
                case "complete": statusIcon = "\u{001B}[32m\u{2713}\u{001B}[0m"
                case "partial": statusIcon = "\u{001B}[33m~\u{001B}[0m"
                case "not started": statusIcon = " "
                default: statusIcon = "\u{001B}[31m\u{2717}\u{001B}[0m"
                }
                print("  \(statusIcon) \(s.phase.rawValue.padding(toLength: 28, withPad: " ", startingAt: 0))  \(s.status.padding(toLength: 12, withPad: " ", startingAt: 0))  \(s.fileCount)")
            }
            if detail.availableCommits.count > 1 {
                print("\n  Available commits:")
                for c in detail.availableCommits {
                    let marker = (c == detail.commitHash) ? " (current)" : ""
                    print("    \(c)\(marker)")
                }
            }
            print("")
            printReviewSection(reviews: reviews, prNumber: options.prNumber)
            printCheckRunSection(checkRuns: checkRuns, prNumber: options.prNumber)
        }
    }

    private func printReviewSection(reviews: [GitHubReview]?, prNumber: Int) {
        print("  Reviews:")
        guard let reviews else {
            print("    (not loaded — run prradar refresh-pr \(prNumber))")
            return
        }
        let approved = reviews.filter { $0.state == .approved }.compactMap { $0.author?.login }
        let changesRequested = reviews.filter { $0.state == .changesRequested }.compactMap { $0.author?.login }
        let pending = reviews.filter { $0.state == .pending }.compactMap { $0.author?.login }
        if approved.isEmpty && changesRequested.isEmpty && pending.isEmpty {
            print("    No reviews")
            return
        }
        for login in approved {
            print("    \u{001B}[32m\u{2713}\u{001B}[0m Approved by: @\(login)")
        }
        for login in changesRequested {
            print("    \u{001B}[31m\u{2717}\u{001B}[0m Changes requested by: @\(login)")
        }
        for login in pending {
            print("    \u{001B}[33m\u{25CB}\u{001B}[0m Review pending: @\(login)")
        }
    }

    private func printCheckRunSection(checkRuns: [GitHubCheckRun]?, prNumber: Int) {
        print("  Checks:")
        guard let checkRuns else {
            print("    (not loaded — run prradar refresh-pr \(prNumber))")
            return
        }
        if checkRuns.isEmpty {
            print("    No check runs")
            return
        }
        let failing = checkRuns.filter { $0.isFailing }
        let pending = checkRuns.filter { $0.status == .inProgress || $0.status == .queued }
        let passing = checkRuns.filter { $0.isPassing }
        if failing.isEmpty && pending.isEmpty {
            print("    \u{001B}[32m\u{2713}\u{001B}[0m All \(passing.count) check(s) passing")
        } else {
            if !failing.isEmpty {
                print("    \u{001B}[31m\u{2717}\u{001B}[0m \(failing.count) failing")
                for run in failing {
                    print("      - \(run.name)")
                }
            }
            if !pending.isEmpty {
                print("    \u{23F3} \(pending.count) pending")
                for run in pending {
                    print("      - \(run.name)")
                }
            }
            if !passing.isEmpty {
                print("    \u{001B}[32m\u{2713}\u{001B}[0m \(passing.count) passing")
            }
        }
    }
}
