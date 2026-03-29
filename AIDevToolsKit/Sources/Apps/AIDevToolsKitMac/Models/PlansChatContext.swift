import AIOutputSDK
import Foundation
import MarkdownPlannerService
import RepositorySDK
import SwiftUI

@MainActor
final class PlansChatContext: ViewChatContext {

    let chatSystemPrompt: String = "You are in the Plans tab. The user can view, generate, execute, and iterate on implementation plans."
    let responseRouter: AIResponseRouter

    private let plannerModel: MarkdownPlannerModel
    private let workspaceModel: WorkspaceModel

    var chatContextIdentifier: String {
        "plans-\(workspaceModel.selectedRepository?.id.uuidString ?? "none")"
    }

    var chatWorkingDirectory: String {
        workspaceModel.selectedRepository?.path.path(percentEncoded: false) ?? ""
    }

    init(
        plannerModel: MarkdownPlannerModel,
        workspaceModel: WorkspaceModel,
        selectedPlanName: Binding<String?>
    ) {
        self.plannerModel = plannerModel
        self.workspaceModel = workspaceModel

        let router = AIResponseRouter()

        router.addRoute(
            AIResponseDescriptor(
                name: "getPlanDetails",
                description: "Get details for a specific plan by name",
                jsonSchema: #"{"type":"object","required":["name"],"properties":{"name":{"type":"string"}}}"#,
                kind: .query
            ),
            type: NameInput.self
        ) { input in
            await MainActor.run {
                guard let plan = plannerModel.plans.first(where: { $0.name == input.name }) else {
                    return "{\"error\":\"Plan not found\"}"
                }
                return encodeToString(PlanDetailsResponse(
                    completedPhases: plan.completedPhases,
                    filePath: plan.planURL.path(percentEncoded: false),
                    isFullyCompleted: plan.isFullyCompleted,
                    name: plan.name,
                    totalPhases: plan.totalPhases
                ))
            }
        }

        router.addRoute(
            AIResponseDescriptor(
                name: "getViewState",
                description: "Get current state: selected plan, all plans with completion status, execution state",
                jsonSchema: #"{"type":"object"}"#,
                kind: .query
            ),
            type: EmptyInput.self
        ) { _ in
            await MainActor.run {
                let response = ViewStateResponse(
                    executionState: executionStateString(plannerModel.state),
                    plans: plannerModel.plans.map { plan in
                        ViewStateResponse.PlanSummary(
                            completedPhases: plan.completedPhases,
                            isFullyCompleted: plan.isFullyCompleted,
                            name: plan.name,
                            totalPhases: plan.totalPhases
                        )
                    },
                    selectedPlan: selectedPlanName.wrappedValue
                )
                return encodeToString(response)
            }
        }

        router.addRoute(
            AIResponseDescriptor(
                name: "navigateToTab",
                description: "Navigate to a workspace tab",
                jsonSchema: #"{"type":"object","required":["tab"],"properties":{"tab":{"type":"string","enum":["architecture","claudeChain","evals","plans","prradar","skills"]}}}"#,
                kind: .action
            ),
            type: TabInput.self
        ) { input in
            await MainActor.run {
                UserDefaults.standard.setValue(input.tab, forKey: "selectedWorkspaceTab")
                return nil as String?
            }
        }

        router.addRoute(
            AIResponseDescriptor(
                name: "reloadPlans",
                description: "Reload the plan list from disk",
                jsonSchema: #"{"type":"object"}"#,
                kind: .action
            ),
            type: EmptyInput.self
        ) { _ in
            await plannerModel.reloadPlans()
            return nil
        }

        router.addRoute(
            AIResponseDescriptor(
                name: "selectPlan",
                description: "Select a plan in the sidebar by name",
                jsonSchema: #"{"type":"object","required":["name"],"properties":{"name":{"type":"string"}}}"#,
                kind: .action
            ),
            type: NameInput.self
        ) { input in
            await MainActor.run {
                selectedPlanName.wrappedValue = input.name
                return nil as String?
            }
        }

        self.responseRouter = router
    }
}

// MARK: - Private Types

private struct EmptyInput: Decodable, Sendable {}
private struct NameInput: Decodable, Sendable { let name: String }
private struct TabInput: Decodable, Sendable { let tab: String }

private struct PlanDetailsResponse: Encodable {
    let completedPhases: Int
    let filePath: String
    let isFullyCompleted: Bool
    let name: String
    let totalPhases: Int
}

private struct ViewStateResponse: Encodable {
    let executionState: String
    let plans: [PlanSummary]
    let selectedPlan: String?

    struct PlanSummary: Encodable {
        let completedPhases: Int
        let isFullyCompleted: Bool
        let name: String
        let totalPhases: Int
    }
}

// MARK: - Helpers

private func encodeToString<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func executionStateString(_ state: MarkdownPlannerModel.State) -> String {
    switch state {
    case .completed: return "completed"
    case .error: return "error"
    case .executing: return "executing"
    case .generating: return "generating"
    case .idle: return "idle"
    }
}
