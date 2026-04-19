import AIOutputSDK
import DataPathsService
import Foundation
import Logging
import PipelineSDK
import PipelineService
import PlanFeature
import PlanService
import ProviderRegistryService
import RepositorySDK

@MainActor @Observable
final class PlanModel {

    struct QueuedTask: Identifiable {
        let id: UUID
        let description: String

        init(id: UUID = UUID(), description: String) {
            self.id = id
            self.description = description
        }
    }

    indirect enum State {
        case idle
        case executing
        case generating(step: String)
        case completed(PlanService.ExecuteResult, phases: [PlanPhase])
        case loadingPlans(prior: State)
        case error(Error)

        var lastExecutionPhases: [PlanPhase] {
            switch self {
            case .completed(_, let phases): return phases
            case .loadingPlans(let prior): return prior.lastExecutionPhases
            default: return []
            }
        }

        var completionResult: PlanService.ExecuteResult? {
            switch self {
            case .completed(let result, _): return result
            case .loadingPlans(let prior): return prior.completionResult
            default: return nil
            }
        }
    }

    private let logger = Logger(label: "PlanModel")

    private(set) var completedPlans: [MarkdownPlanEntry] = []
    private(set) var plans: [MarkdownPlanEntry] = []
    private(set) var state: State = .idle
    let pipelineModel = PipelineModel()
    private(set) var executionCompleteCount: Int = 0
    private(set) var phaseCompleteCount: Int = 0
    private(set) var currentRepository: RepositoryConfiguration?
    private(set) var queuedTasks: [QueuedTask] = []

    var selectedProviderName: String {
        didSet {
            if oldValue != selectedProviderName {
                rebuildClient()
            }
        }
    }

    var availableProviders: [(name: String, displayName: String)] {
        providerRegistry.providers.map { (name: $0.name, displayName: $0.displayName) }
    }

    private var activeClient: any AIClient
    @ObservationIgnored private var chatModels: [String: ChatModel] = [:]
    private let dependencies: Dependencies
    private let dataPathsService: DataPathsService?
    private let deletePlanUseCase: DeletePlanUseCase
    private let mcpConfigPath: String?
    private let providerRegistry: ProviderRegistry
    private let togglePhaseUseCase: TogglePhaseUseCase

    init(
        dataPathsService: DataPathsService? = nil,
        deletePlanUseCase: DeletePlanUseCase = DeletePlanUseCase(),
        mcpConfigPath: String? = nil,
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil,
        togglePhaseUseCase: TogglePhaseUseCase = TogglePhaseUseCase()
    ) {
        self.dataPathsService = dataPathsService
        self.deletePlanUseCase = deletePlanUseCase
        self.mcpConfigPath = mcpConfigPath
        self.providerRegistry = providerRegistry
        self.togglePhaseUseCase = togglePhaseUseCase
        self.dependencies = Dependencies()

        guard let client = selectedProviderName.flatMap({ providerRegistry.client(named: $0) })
            ?? providerRegistry.defaultClient else {
            preconditionFailure("PlanModel requires at least one configured provider")
        }
        self.selectedProviderName = client.name
        self.activeClient = client
    }

    private func rebuildClient() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        activeClient = client
    }

    func loadPlans(for repo: RepositoryConfiguration) async {
        if currentRepository?.id != repo.id {
            chatModels = [:]
        }
        currentRepository = repo
        plans = []
        completedPlans = []
        let prior: State = {
            if case .loadingPlans(let inner) = state { return inner }
            return state
        }()
        state = .loadingPlans(prior: prior)
        let proposedDir = resolvedProposedDirectory(for: repo)
        let completedDir = resolvedCompletedDirectory(for: repo)
        async let proposedTask = dependencies.loadPlans(proposedDir)
        async let completedTask = dependencies.loadPlans(completedDir)
        let (proposed, completed) = await (proposedTask, completedTask)
        guard self.currentRepository?.id == repo.id else {
            state = prior
            return
        }
        self.plans = proposed
        self.completedPlans = completed
        state = prior
    }

    func deletePlan(_ plan: MarkdownPlanEntry) throws {
        try deletePlanUseCase.run(planURL: plan.planURL)
        completedPlans.removeAll { $0.id == plan.id }
        plans.removeAll { $0.id == plan.id }
    }

    func reloadPlans() async {
        guard let repo = currentRepository else { return }
        await loadPlans(for: repo)
    }

    func getPlanDetails(planName: String, repository: RepositoryConfiguration) async throws -> String {
        let directory = completedPlans.contains(where: { $0.name == planName })
            ? resolvedCompletedDirectory(for: repository)
            : resolvedProposedDirectory(for: repository)
        return try await dependencies.getPlanDetails(planName, directory)
    }

    func togglePhase(plan: MarkdownPlanEntry, phaseIndex: Int) throws -> String {
        let updatedContent = try togglePhaseUseCase.run(planURL: plan.planURL, phaseIndex: phaseIndex)
        Task { await reloadPlans() }
        return updatedContent
    }

    func completePlan(_ plan: MarkdownPlanEntry, repository: RepositoryConfiguration) throws {
        let settings = repository.planner ?? PlanRepoSettings()
        let completedDir = settings.resolvedCompletedDirectory(repoPath: repository.path)
        try dependencies.completePlan(plan.planURL, completedDir)
        Task { await reloadPlans() }
    }

    func execute(
        plan: MarkdownPlanEntry,
        repository: RepositoryConfiguration,
        chatModel: ChatModel? = nil,
        executeMode: PlanService.ExecuteMode = .all,
        stopAfterArchitectureDiagram: Bool = false,
        useWorktree: Bool = false
    ) async {
        state = .executing
        phaseCompleteCount = 0

        if let chatModel {
            pipelineModel.onEvent = { @MainActor [weak chatModel] event in
                chatModel?.handlePipelineEvent(event)
            }
        }
        defer { pipelineModel.onEvent = nil }

        do {
            let worktreeOptions = useWorktree ? computePlanWorktreeOptions(plan: plan, repoPath: repository.path) : nil
            let options = PlanService.ExecuteOptions(
                executeMode: executeMode,
                planPath: plan.planURL,
                repoPath: repository.path,
                repository: repository,
                stopAfterArchitectureDiagram: stopAfterArchitectureDiagram,
                worktreeOptions: worktreeOptions
            )
            let blueprint = try await dependencies.planService(activeClient).buildExecutePipeline(
                options: options,
                pendingTasksProvider: { [weak self] in
                    guard let self else { return [] }
                    return await MainActor.run { self.clearQueue().map(\.description) }
                }
            )
            try await pipelineModel.run(blueprint: blueprint)
            let (completedCount, totalCount) = try readPhaseCount(from: plan.planURL)
            let allCompleted = totalCount > 0 && completedCount == totalCount
            if allCompleted {
                logger.info("execute: all \(totalCount) phases completed", metadata: ["plan": "\(plan.planURL.lastPathComponent)"])
            } else {
                logger.warning("execute: stopped with \(completedCount)/\(totalCount) phases completed", metadata: ["plan": "\(plan.planURL.lastPathComponent)"])
            }
            let result = PlanService.ExecuteResult(
                phasesExecuted: completedCount,
                totalPhases: totalCount,
                allCompleted: allCompleted,
                totalSeconds: 0
            )
            state = .completed(result, phases: [])
            executionCompleteCount += 1
            await loadPlans(for: repository)
        } catch {
            state = .error(error)
        }
    }

    @discardableResult
    func generate(prompt: String, repositories: [RepositoryConfiguration], selectedRepository: RepositoryConfiguration? = nil) async -> String? {
        state = .generating(step: selectedRepository != nil ? "Generating plan..." : "Matching repository...")

        let options = PlanService.GenerateOptions(
            prompt: prompt,
            repositories: repositories,
            selectedRepository: selectedRepository
        )

        do {
            let result = try await dependencies.planService(activeClient).generate(options: options) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    switch progress {
                    case .matchingRepo:
                        self.state = .generating(step: "Matching repository...")
                    case .matchedRepo(_, let request):
                        self.state = .generating(step: "Matched: \(request)")
                    case .generatingPlan:
                        self.state = .generating(step: "Generating plan...")
                    case .generatedPlan(let filename):
                        self.state = .generating(step: "Generated: \(filename)")
                    case .writingPlan:
                        self.state = .generating(step: "Writing plan...")
                    case .completed:
                        break
                    }
                }
            }
            await loadPlans(for: result.repository)
            let planName = result.planURL.deletingPathExtension().lastPathComponent
            state = .idle
            return planName
        } catch {
            state = .error(error)
            return nil
        }
    }

    func persistentChatModel(for planName: String, workingDirectory: String, systemPrompt: String) -> ChatModel {
        if let existing = chatModels[planName] { return existing }
        let model = makeChatModel(workingDirectory: workingDirectory, systemPrompt: systemPrompt)
        chatModels[planName] = model
        return model
    }

    func makeChatModel(workingDirectory: String, systemPrompt: String? = nil) -> ChatModel {
        let settings = ChatSettings()
        settings.resumeLastSession = false
        return ChatModel(configuration: ChatModelConfiguration(
            client: activeClient,
            mcpConfigPath: mcpConfigPath,
            settings: settings,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory
        ))
    }

    func queueTask(_ description: String) {
        queuedTasks.append(QueuedTask(description: description))
    }

    func removeQueuedTask(_ id: UUID) {
        queuedTasks.removeAll { $0.id == id }
    }

    func clearQueue() -> [QueuedTask] {
        let tasks = queuedTasks
        queuedTasks = []
        return tasks
    }

    func appendReviewTemplate(_ template: ReviewTemplate, to planURL: URL) async throws {
        try await dependencies.appendReviewTemplate(template, planURL)
    }

    func savePlanContent(_ content: String, to planURL: URL) async throws {
        try await dependencies.savePlanContent(content, planURL)
        await reloadPlans()
    }

    func reportError(_ error: Error) {
        state = .error(error)
    }

    func reset() {
        state = .idle
    }

    // MARK: - Private

    private struct Dependencies {
        let appendReviewTemplate: @Sendable (ReviewTemplate, URL) async throws -> Void
        let completePlan: @Sendable (URL, URL) throws -> Void
        let getPlanDetails: @Sendable (String, URL) async throws -> String
        let loadPlans: @Sendable (URL) async -> [MarkdownPlanEntry]
        let planService: @Sendable (any AIClient) -> PlanService
        let savePlanContent: @Sendable (String, URL) async throws -> Void

        init(
            appendReviewTemplate: @escaping @Sendable (ReviewTemplate, URL) async throws -> Void = { template, planURL in
                try await AppendReviewTemplateUseCase().run(.init(planURL: planURL, template: template))
            },
            completePlan: @escaping @Sendable (URL, URL) throws -> Void = { planURL, completedDirectory in
                try CompletePlanUseCase(completedDirectory: completedDirectory).run(planURL: planURL)
            },
            getPlanDetails: @escaping @Sendable (String, URL) async throws -> String = { planName, directory in
                try await GetPlanDetailsUseCase(proposedDirectory: directory).run(planName: planName)
            },
            loadPlans: @escaping @Sendable (URL) async -> [MarkdownPlanEntry] = { directory in
                await LoadPlansUseCase(proposedDirectory: directory).run()
            },
            planService: @escaping @Sendable (any AIClient) -> PlanService = { client in
                PlanService(
                    client: client,
                    resolveProposedDirectory: { repo in
                        let settings = repo.planner ?? PlanRepoSettings()
                        return settings.resolvedProposedDirectory(repoPath: repo.path)
                    }
                )
            },
            savePlanContent: @escaping @Sendable (String, URL) async throws -> Void = { content, planURL in
                try SavePlanContentUseCase().run(content: content, planURL: planURL)
            }
        ) {
            self.appendReviewTemplate = appendReviewTemplate
            self.completePlan = completePlan
            self.getPlanDetails = getPlanDetails
            self.loadPlans = loadPlans
            self.planService = planService
            self.savePlanContent = savePlanContent
        }
    }

    private func computePlanWorktreeOptions(plan: MarkdownPlanEntry, repoPath: URL) -> WorktreeOptions? {
        guard let service = dataPathsService else { return nil }
        let branchName = PlanService.worktreeBranchName(for: plan.planURL)
        // Swallowing intentionally: worktree creation is best-effort; returning nil falls back to non-worktree execution.
        guard let worktreesDir = try? service.path(for: .planWorktrees) else { return nil }
        let destinationPath = worktreesDir.appendingPathComponent(branchName).path
        return WorktreeOptions(
            branchName: branchName,
            destinationPath: destinationPath,
            repoPath: repoPath.path,
            basedOn: "HEAD"
        )
    }

    private func resolvedCompletedDirectory(for repo: RepositoryConfiguration) -> URL {
        let settings = repo.planner ?? PlanRepoSettings()
        return settings.resolvedCompletedDirectory(repoPath: repo.path)
    }

    private func resolvedProposedDirectory(for repo: RepositoryConfiguration) -> URL {
        let settings = repo.planner ?? PlanRepoSettings()
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }

    private func readPhaseCount(from planURL: URL) throws -> (completed: Int, total: Int) {
        let content = try String(contentsOf: planURL, encoding: .utf8)
        var completed = 0
        var total = 0
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## - [x] ") {
                completed += 1
                total += 1
            } else if line.hasPrefix("## - [ ] ") {
                total += 1
            }
        }
        return (completed, total)
    }
}
