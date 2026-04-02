import CLISDK
import Foundation
import GitSDK
import PipelineSDK

public struct PRConfiguration: Sendable {
    public let assignees: [String]
    public let labels: [String]
    public let maxOpenPRs: Int?
    public let reviewers: [String]

    public init(
        assignees: [String] = [],
        labels: [String] = [],
        maxOpenPRs: Int? = nil,
        reviewers: [String] = []
    ) {
        self.assignees = assignees
        self.labels = labels
        self.maxOpenPRs = maxOpenPRs
        self.reviewers = reviewers
    }
}

public struct PRStep: PipelineNode {
    public static var prNumberKey: PipelineContextKey<String> { .init("PRStep.prNumber") }
    public static var prURLKey: PipelineContextKey<String> { .init("PRStep.prURL") }

    public let baseBranch: String
    public let configuration: PRConfiguration
    public let displayName: String
    public let gitClient: GitClient
    public let id: String

    private let cliClient: CLIClient

    public init(
        id: String,
        displayName: String,
        baseBranch: String,
        configuration: PRConfiguration,
        gitClient: GitClient,
        cliClient: CLIClient = CLIClient()
    ) {
        self.baseBranch = baseBranch
        self.cliClient = cliClient
        self.configuration = configuration
        self.displayName = displayName
        self.gitClient = gitClient
        self.id = id
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        let workingDirectory = context[PipelineContext.workingDirectoryKey] ?? ""
        let branch = try await gitClient.getCurrentBranch(workingDirectory: workingDirectory)

        try await gitClient.push(
            remote: "origin",
            branch: branch,
            setUpstream: true,
            force: true,
            workingDirectory: workingDirectory
        )

        let repoSlug = try await detectRepoSlug(workingDirectory: workingDirectory)

        if let maxOpen = configuration.maxOpenPRs, !repoSlug.isEmpty {
            let openCount = try await countOpenPRs(repoSlug: repoSlug, workingDirectory: workingDirectory)
            guard openCount < maxOpen else {
                throw PipelineError.capacityExceeded(openCount: openCount, maxOpen: maxOpen)
            }
        }

        var prCreateArgs = [
            "pr", "create",
            "--draft",
            "--head", branch,
            "--base", baseBranch,
        ]
        if !repoSlug.isEmpty {
            prCreateArgs += ["--repo", repoSlug]
        }
        for label in configuration.labels {
            prCreateArgs += ["--label", label]
        }
        for assignee in configuration.assignees {
            prCreateArgs += ["--assignee", assignee]
        }
        for reviewer in configuration.reviewers {
            prCreateArgs += ["--reviewer", reviewer]
        }

        let prURL: String
        do {
            let result = try await cliClient.execute(
                command: "gh",
                arguments: prCreateArgs,
                workingDirectory: workingDirectory,
                environment: nil,
                printCommand: false
            )
            guard result.isSuccess else {
                throw PRStepError.commandFailed(command: "gh pr create", output: result.errorOutput)
            }
            prURL = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as PRStepError {
            throw error
        } catch {
            // Already-exists recovery
            var viewArgs = ["pr", "view", branch, "--json", "url", "--jq", ".url"]
            if !repoSlug.isEmpty { viewArgs += ["--repo", repoSlug] }
            let viewResult = try await cliClient.execute(
                command: "gh",
                arguments: viewArgs,
                workingDirectory: workingDirectory,
                environment: nil,
                printCommand: false
            )
            prURL = viewResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prNumber = try await fetchPRNumber(branch: branch, repoSlug: repoSlug, workingDirectory: workingDirectory)

        if let metrics = context[AITask<String>.metricsKey], let cost = metrics.cost {
            try await postCostComment(
                prNumber: prNumber,
                repoSlug: repoSlug,
                cost: cost,
                workingDirectory: workingDirectory
            )
        }

        var updated = context
        updated[Self.prURLKey] = prURL
        updated[Self.prNumberKey] = prNumber
        return updated
    }

    // MARK: - Private

    private func detectRepoSlug(workingDirectory: String) async throws -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        let remoteURL = try await gitClient.remoteGetURL(workingDirectory: workingDirectory)
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func countOpenPRs(repoSlug: String, workingDirectory: String) async throws -> Int {
        var args = ["pr", "list", "--state", "open", "--json", "number"]
        if !repoSlug.isEmpty { args += ["--repo", repoSlug] }
        let result = try await cliClient.execute(
            command: "gh",
            arguments: args,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard result.isSuccess, let data = result.stdout.data(using: .utf8) else { return 0 }
        let numbers = (try? JSONDecoder().decode([[String: Int]].self, from: data)) ?? []
        return numbers.count
    }

    private func fetchPRNumber(branch: String, repoSlug: String, workingDirectory: String) async throws -> String {
        var args = ["pr", "view", branch, "--json", "number"]
        if !repoSlug.isEmpty { args += ["--repo", repoSlug] }
        let result = try await cliClient.execute(
            command: "gh",
            arguments: args,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard result.isSuccess, let data = result.stdout.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: Int].self, from: data),
              let number = json["number"] else {
            throw PRStepError.commandFailed(command: "gh pr view", output: result.errorOutput)
        }
        return String(number)
    }

    private func postCostComment(prNumber: String, repoSlug: String, cost: Double, workingDirectory: String) async throws {
        let body = String(format: "**AI cost:** $%.4f", cost)
        var args = ["pr", "comment", prNumber, "--body", body]
        if !repoSlug.isEmpty { args += ["--repo", repoSlug] }
        _ = try await cliClient.execute(
            command: "gh",
            arguments: args,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
    }
}

public enum PRStepError: Error, Sendable {
    case commandFailed(command: String, output: String)
}
