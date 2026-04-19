import Foundation

public struct IPCUIState: Codable, Sendable {
    public let activeDiffContext: IPCDiffContext?
    public let activePlanContext: IPCPlanContext?
    public let currentTab: String?
    public let selectedChainName: String?
    public let selectedPlanName: String?

    public init(
        activeDiffContext: IPCDiffContext? = nil,
        activePlanContext: IPCPlanContext? = nil,
        currentTab: String?,
        selectedChainName: String?,
        selectedPlanName: String?
    ) {
        self.activeDiffContext = activeDiffContext
        self.activePlanContext = activePlanContext
        self.currentTab = currentTab
        self.selectedChainName = selectedChainName
        self.selectedPlanName = selectedPlanName
    }
}
