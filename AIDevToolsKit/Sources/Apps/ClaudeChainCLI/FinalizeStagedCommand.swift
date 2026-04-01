import AIOutputSDK
import AnthropicSDK
import ArgumentParser
import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import Foundation
import ProviderRegistryService

struct FinalizeStagedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "finalize-staged",
        abstract: "Create a PR from a branch staged by run-task --staging-only"
    )

    @Option(help: "Project name within claude-chain/ directory")
    var project: String

    @Option(help: "Branch name to push and create a PR from")
    var branchName: String

    @Option(help: "Task description (must match the staged task exactly)")
    var taskDescription: String

    @Option(help: "Base branch for the PR (overrides configuration.yml)")
    var baseBranch: String?

    @Option(help: "Path to the repository root (defaults to current directory)")
    var repoPath: String?

    @Option(help: "AI provider name to override the default")
    var provider: String?

    @Option(help: "Credential account name to override auto-detection")
    var githubAccount: String?

    public init() {}

    func run() async throws {
        let repoURL: URL
        if let repoPath {
            repoURL = URL(fileURLWithPath: (repoPath as NSString).standardizingPath)
        } else {
            repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        let service = SecureSettingsService()
        let account = githubAccount ?? (try? service.listCredentialAccounts())?.first ?? "default"
        let resolver = CredentialResolver(settingsService: service, githubAccount: account)

        if case .token(let token) = resolver.getGitHubAuth() {
            setenv("GH_TOKEN", token, 1)
        }

        let registry = makeRegistry(credentialResolver: resolver)
        guard let client = provider.flatMap({ registry.client(named: $0) }) ?? registry.defaultClient else {
            print("Error: No AI provider available. Configure an API key or install Claude CLI.")
            throw ExitCode.failure
        }

        let resolvedBaseBranch: String
        if let baseBranch {
            resolvedBaseBranch = baseBranch
        } else {
            let chainDir = repoURL.appendingPathComponent("claude-chain").path
            let chainProject = Project(
                name: project,
                basePath: (chainDir as NSString).appendingPathComponent(project)
            )
            let githubClient = GitHubClient(workingDirectory: chainDir)
            let repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))
            let config = (try? repository.loadLocalConfiguration(project: chainProject))
                ?? ProjectConfiguration.default(project: chainProject)
            resolvedBaseBranch = config.getBaseBranch(defaultBaseBranch: Constants.defaultBaseBranch)
        }

        print("=== Finalize Staged Task ===")
        print("Project: \(project)")
        print("Branch: \(branchName)")
        print("Task: \(taskDescription)")
        print("Provider: \(client.name)")
        print()

        let useCase = FinalizeStagedTaskUseCase(client: client)
        let result = try await useCase.run(
            options: .init(
                repoPath: repoURL,
                projectName: project,
                baseBranch: resolvedBaseBranch,
                branchName: branchName,
                taskDescription: taskDescription
            )
        ) { progress in
            Self.handleProgress(progress)
        }

        print()
        if result.success {
            print("=== PR Created ===")
            print(result.message)
            if let prURL = result.prURL {
                print("PR: \(prURL)")
            }
        } else {
            print("=== Failed ===")
            print(result.message)
            throw ExitCode.failure
        }
    }

    private static func handleProgress(_ progress: RunChainTaskUseCase.Progress) {
        switch progress {
        case .finalizing:
            print("=== Phase: Finalizing ===")
            print("Marking task complete, pushing branch, creating PR...")
        case .prCreated(let prNumber, let prURL):
            print("PR #\(prNumber) created: \(prURL)")
        case .generatingSummary:
            print("\n=== Phase: PR Summary ===")
            print("Generating PR summary...")
        case .summaryStreamEvent:
            break
        case .summaryCompleted(let summary):
            print("Summary generated (\(summary.count) chars)")
        case .postingPRComment:
            print("\n=== Phase: Post PR Comment ===")
        case .prCommentPosted:
            print("PR comment posted.")
        case .completed(let prURL):
            if let prURL {
                print("\n=== Completed === PR: \(prURL)")
            } else {
                print("\n=== Completed ===")
            }
        case .failed(let phase, let error):
            print("\nFailed during \(phase): \(error)")
        default:
            break
        }
    }

    private func makeRegistry(credentialResolver: CredentialResolver) -> ProviderRegistry {
        var providers: [any AIClient] = [
            ClaudeProvider(),
            CodexProvider(),
        ]
        if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key)))
        }
        return ProviderRegistry(providers: providers)
    }
}
