import AppIPCSDK
import Observation

@MainActor @Observable
final class MCPContextModel {
    private(set) var activeDiffContext: IPCDiffContext?
    private(set) var activePlanContext: IPCPlanContext?

    func clearDiffContext() {
        activeDiffContext = nil
    }

    func clearPlanContext(planFilePath: String? = nil) {
        guard let planFilePath else {
            activePlanContext = nil
            return
        }

        guard activePlanContext?.planFilePath == planFilePath else { return }
        activePlanContext = nil
    }

    func updateDiffContext(_ context: IPCDiffContext?) {
        activeDiffContext = context
    }

    func updatePlanContext(planName: String, planFilePath: String, completedPhases: [String]) {
        activePlanContext = IPCPlanContext(
            completedPhases: completedPhases,
            planFilePath: planFilePath,
            planName: planName
        )
    }
}
