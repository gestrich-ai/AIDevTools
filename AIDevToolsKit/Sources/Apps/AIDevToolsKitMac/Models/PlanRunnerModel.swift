import Foundation
import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK

public struct PlanPhase: Identifiable {
    public var id: Int { index }
    public let index: Int
    public let description: String
    public let isCompleted: Bool

    public init(index: Int, description: String, isCompleted: Bool) {
        self.index = index
        self.description = description
        self.isCompleted = isCompleted
    }
}

@MainActor @Observable
public final class PlanRunnerModel {

    public enum State {
        case idle
        case executing(progress: ExecutionProgress)
        case generating(step: String)
        case completed(ExecutePlanUseCase.Result)
        case error(Error)
    }

    public struct ExecutionProgress {
        public var phases: [PhaseStatus] = []
        public var currentPhaseIndex: Int?
        public var currentPhaseDescription: String = ""
        public var currentOutput: String = ""
        public var phasesCompleted: Int = 0
        public var totalPhases: Int = 0
    }

    public var state: State = .idle
    public var plans: [PlanEntry] = []
    public var executionCompleteCount: Int = 0
    public private(set) var currentRepository: RepositoryInfo?

    private let deletePlanUseCase: DeletePlanUseCase
    private let executePlan: ExecutePlanUseCase
    private let generatePlan: GeneratePlanUseCase
    private let loadPlansUseCase: LoadPlansUseCase
    private let planSettingsStore: PlanRepoSettingsStore

    public init(
        deletePlanUseCase: DeletePlanUseCase = DeletePlanUseCase(),
        executePlan: ExecutePlanUseCase = ExecutePlanUseCase(),
        generatePlan: GeneratePlanUseCase = GeneratePlanUseCase(),
        loadPlansUseCase: LoadPlansUseCase = LoadPlansUseCase(),
        planSettingsStore: PlanRepoSettingsStore
    ) {
        self.deletePlanUseCase = deletePlanUseCase
        self.executePlan = executePlan
        self.generatePlan = generatePlan
        self.loadPlansUseCase = loadPlansUseCase
        self.planSettingsStore = planSettingsStore
    }

    public func loadPlans(for repo: RepositoryInfo) {
        currentRepository = repo
        let proposedDir = resolvedProposedDirectory(for: repo)
        plans = loadPlansUseCase.run(proposedDirectory: proposedDir)
    }

    public func deletePlan(_ plan: PlanEntry) throws {
        try deletePlanUseCase.run(planURL: plan.planURL)
        plans.removeAll { $0.id == plan.id }
    }

    public func reloadPlans() {
        guard let repo = currentRepository else { return }
        loadPlans(for: repo)
    }

    public func execute(plan: PlanEntry, repository: RepositoryInfo) async {
        state = .executing(progress: ExecutionProgress())

        let settings = (try? planSettingsStore.settings(forRepoId: repository.id)) ?? PlanRepoSettings(repoId: repository.id)
        let options = ExecutePlanUseCase.Options(
            planPath: plan.planURL,
            repoPath: repository.path,
            repository: repository,
            completedDirectory: settings.resolvedCompletedDirectory(repoPath: repository.path)
        )

        do {
            let result = try await executePlan.run(options) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    self.handleExecutionProgress(progress)
                }
            }
            state = .completed(result)
            executionCompleteCount += 1
            loadPlans(for: repository)
        } catch {
            state = .error(error)
        }
    }

    public func generate(voiceText: String, repositories: [RepositoryInfo]) async {
        state = .generating(step: "Matching repository...")

        let settingsStore = planSettingsStore
        let options = GeneratePlanUseCase.Options(
            voiceText: voiceText,
            repositories: repositories,
            resolveProposedDirectory: { repo in
                let settings = (try? settingsStore.settings(forRepoId: repo.id)) ?? PlanRepoSettings(repoId: repo.id)
                return settings.resolvedProposedDirectory(repoPath: repo.path)
            }
        )

        do {
            let result = try await generatePlan.run(options) { [weak self] progress in
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
            loadPlans(for: result.repository)
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    public func reset() {
        state = .idle
    }

    // MARK: - Private

    private func handleExecutionProgress(_ progress: ExecutePlanUseCase.Progress) {
        guard case .executing(var current) = state else { return }

        switch progress {
        case .fetchingStatus:
            break
        case .phaseOverview(let phases):
            current.phases = phases
            current.totalPhases = phases.count
        case .startingPhase(let index, let total, let description):
            current.currentPhaseIndex = index
            current.totalPhases = total
            current.currentPhaseDescription = description
            current.currentOutput = ""
        case .phaseOutput(let text):
            current.currentOutput += text
        case .phaseCompleted(let index, _, _):
            current.phasesCompleted = index + 1
            current.currentOutput = ""
            if index < current.phases.count {
                current.phases[index] = PhaseStatus(
                    description: current.phases[index].description,
                    status: "completed"
                )
            }
        case .phaseFailed(_, let description, let error):
            current.currentPhaseDescription = "\(description) — Failed: \(error)"
        case .allCompleted(let phasesExecuted, _):
            current.phasesCompleted = phasesExecuted
        case .timeLimitReached:
            break
        }

        state = .executing(progress: current)
    }

    public static func parsePhases(from content: String) -> [PlanPhase] {
        var phases: [PlanPhase] = []
        var index = 0
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## - [x] ") {
                let desc = String(line.dropFirst("## - [x] ".count))
                phases.append(PlanPhase(index: index, description: desc, isCompleted: true))
                index += 1
            } else if line.hasPrefix("## - [ ] ") {
                let desc = String(line.dropFirst("## - [ ] ".count))
                phases.append(PlanPhase(index: index, description: desc, isCompleted: false))
                index += 1
            }
        }
        return phases
    }

    private func resolvedProposedDirectory(for repo: RepositoryInfo) -> URL {
        let settings = (try? planSettingsStore.settings(forRepoId: repo.id)) ?? PlanRepoSettings(repoId: repo.id)
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }
}
