import AIOutputSDK
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import GitSDK
import PipelineSDK
import PipelineService

public struct ChainRunOptions: Sendable {
    public let baseBranch: String
    public let branchName: String?
    public let dryRun: Bool
    public let githubAccount: String?
    public let projectName: String
    public let repoPath: URL
    public let stagingOnly: Bool

    public init(
        baseBranch: String,
        branchName: String? = nil,
        dryRun: Bool = false,
        githubAccount: String? = nil,
        projectName: String,
        repoPath: URL,
        stagingOnly: Bool = false
    ) {
        self.baseBranch = baseBranch
        self.branchName = branchName
        self.dryRun = dryRun
        self.githubAccount = githubAccount
        self.projectName = projectName
        self.repoPath = repoPath
        self.stagingOnly = stagingOnly
    }
}

public struct ClaudeChainService {
    private let client: any AIClient
    private let git: GitClient

    public init(client: any AIClient, git: GitClient = GitClient()) {
        self.client = client
        self.git = git
    }

    public func buildPipeline(for task: ChainTask, options: ChainRunOptions) async throws -> PipelineBlueprint {
        let repoDir = options.repoPath.path
        let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: options.projectName,
            basePath: (chainDir as NSString).appendingPathComponent(options.projectName)
        )
        let githubClient = GitHubClient(workingDirectory: chainDir)
        let repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))
        let projectConfig = try? repository.loadLocalConfiguration(project: project)

        // Fetch + checkout base branch so spec.md reflects latest remote state
        try await git.fetch(remote: "origin", branch: options.baseBranch, workingDirectory: repoDir)
        try await git.checkout(ref: "FETCH_HEAD", workingDirectory: repoDir)

        // Create feature branch
        let taskHash = TaskService.generateTaskHash(description: task.description)
        let branchName = PRService.formatBranchName(projectName: options.projectName, taskHash: taskHash)
        try await git.checkout(ref: branchName, forceCreate: true, workingDirectory: repoDir)

        // Resolve credentials
        var environment: [String: String]?
        if let githubAccount = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                var env = ProcessInfo.processInfo.environment
                env["GH_TOKEN"] = token
                environment = env
            }
        }

        // Load spec content for instruction enrichment
        let spec = try? repository.loadLocalSpec(project: project)
        let specContent = spec?.content ?? ""
        let taskDescription = task.description

        let instructionBuilder: @Sendable (PendingTask) -> String = { pendingTask in
            """
            Complete the following task from spec.md:

            Task: \(pendingTask.instructions)

            Instructions: Read the entire spec.md file below to understand both WHAT to do and HOW to do it. \
            Follow all guidelines and patterns specified in the document.

            --- BEGIN spec.md ---
            \(specContent)
            --- END spec.md ---

            Now complete the task '\(taskDescription)' following all the details and instructions in the spec.md file above.
            """
        }

        // task.index is 1-based (from SpecTask); MarkdownTaskSource expects 0-based (matches CodeChangeStep.id)
        let specURL = URL(fileURLWithPath: project.specPath)
        let taskSource = MarkdownTaskSource(
            fileURL: specURL,
            format: .task,
            taskIndex: task.index - 1,
            instructionBuilder: instructionBuilder
        )

        let taskSourceNode = TaskSourceNode(
            id: "task-source",
            displayName: "Task: \(task.description)",
            source: taskSource
        )

        var nodes: [any PipelineNode] = [taskSourceNode]
        var manifests: [NodeManifest] = [
            NodeManifest(id: "task-source", displayName: "Task: \(task.description)")
        ]

        if !options.stagingOnly {
            let prConfiguration = PRConfiguration(
                assignees: projectConfig?.assignees ?? [],
                labels: [Constants.defaultPRLabel],
                maxOpenPRs: projectConfig?.maxOpenPRs,
                reviewers: projectConfig?.reviewers ?? []
            )
            let prStep = PRStep(
                id: "pr-step",
                displayName: "Create PR",
                baseBranch: options.baseBranch,
                configuration: prConfiguration,
                gitClient: git,
                projectName: options.projectName,
                taskDescription: task.description
            )
            let commentStep = ChainPRCommentStep(
                id: "pr-comment-step",
                displayName: "Post PR Comment",
                baseBranch: options.baseBranch,
                client: client,
                gitClient: git,
                projectName: options.projectName,
                taskDescription: task.description,
                dryRun: options.dryRun
            )
            nodes.append(prStep)
            nodes.append(commentStep)
            manifests.append(NodeManifest(id: "pr-step", displayName: "Create PR"))
            manifests.append(NodeManifest(id: "pr-comment-step", displayName: "Post PR Comment"))
        }

        let configuration = PipelineConfiguration(
            executionMode: .nextOnly,
            provider: client,
            workingDirectory: repoDir,
            environment: environment
        )

        return PipelineBlueprint(
            nodes: nodes,
            configuration: configuration,
            initialNodeManifest: manifests
        )
    }

    public func buildFinalizePipeline(for task: ChainTask, options: ChainRunOptions) async throws -> PipelineBlueprint {
        let repoDir = options.repoPath.path
        let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: options.projectName,
            basePath: (chainDir as NSString).appendingPathComponent(options.projectName)
        )
        let githubClient = GitHubClient(workingDirectory: chainDir)
        let repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))
        let projectConfig = try? repository.loadLocalConfiguration(project: project)

        // Resolve credentials
        var environment: [String: String]?
        if let githubAccount = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                var env = ProcessInfo.processInfo.environment
                env["GH_TOKEN"] = token
                environment = env
            }
        }

        // Checkout existing staged branch
        if let branchName = options.branchName {
            try await git.checkout(ref: branchName, workingDirectory: repoDir)
        }

        // Mark spec.md checkbox complete and commit before building the blueprint
        let specURL = URL(fileURLWithPath: project.specPath)
        let pipelineSource = MarkdownPipelineSource(fileURL: specURL, format: .task, appendCreatePRStep: false)
        let pipeline = try await pipelineSource.load()
        let codeSteps = pipeline.steps.compactMap { $0 as? CodeChangeStep }
        if let step = codeSteps.first(where: { $0.description == task.description }) {
            try await pipelineSource.markStepCompleted(step)
            try await git.add(files: [specURL.path], workingDirectory: repoDir)
            let staged = try await git.diffCachedNames(workingDirectory: repoDir)
            if !staged.isEmpty {
                let stepIndex = (Int(step.id) ?? 0) + 1
                try await git.commit(
                    message: "Mark task \(stepIndex) as complete in spec.md",
                    workingDirectory: repoDir
                )
            }
        }

        // Blueprint: just PRStep (push + PR creation; code already committed)
        let prConfiguration = PRConfiguration(
            assignees: projectConfig?.assignees ?? [],
            labels: [Constants.defaultPRLabel],
            maxOpenPRs: projectConfig?.maxOpenPRs,
            reviewers: projectConfig?.reviewers ?? []
        )
        let prStep = PRStep(
            id: "pr-step",
            displayName: "Create PR",
            baseBranch: options.baseBranch,
            configuration: prConfiguration,
            gitClient: git,
            projectName: options.projectName,
            taskDescription: task.description
        )
        let commentStep = ChainPRCommentStep(
            id: "pr-comment-step",
            displayName: "Post PR Comment",
            baseBranch: options.baseBranch,
            client: client,
            gitClient: git,
            projectName: options.projectName,
            taskDescription: task.description,
            dryRun: options.dryRun
        )

        let configuration = PipelineConfiguration(
            executionMode: .nextOnly,
            provider: client,
            workingDirectory: repoDir,
            environment: environment
        )

        return PipelineBlueprint(
            nodes: [prStep, commentStep],
            configuration: configuration,
            initialNodeManifest: [
                NodeManifest(id: "pr-step", displayName: "Create PR"),
                NodeManifest(id: "pr-comment-step", displayName: "Post PR Comment"),
            ]
        )
    }
}
