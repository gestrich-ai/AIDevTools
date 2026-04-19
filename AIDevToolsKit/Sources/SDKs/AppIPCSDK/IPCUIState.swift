import Foundation

/// Snapshot of the Mac app UI state exposed to external tools over IPC.
public struct IPCUIState: Codable, Sendable {
    /// Workspace tabs that external tools may care about when interpreting UI state.
    public enum WorkspaceTab: String, Codable, Sendable {
        case architecture
        case claudeChain
        case evals
        case plans
        case prradar
        case repoExplorer
        case skills
        case worktrees

        public var displayName: String {
            switch self {
            case .architecture:
                "Architecture"
            case .claudeChain:
                "Chains"
            case .evals:
                "Evals"
            case .plans:
                "Plans"
            case .prradar:
                "PR Radar"
            case .repoExplorer:
                "Repo Explorer"
            case .skills:
                "Skills"
            case .worktrees:
                "Worktrees"
            }
        }
    }

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

    public var selectedTab: WorkspaceTab? {
        guard let currentTab else { return nil }
        return WorkspaceTab(rawValue: currentTab)
    }

    /// Returns detail lines only for the currently selected tab.
    public func activeTabDetailText() -> String? {
        let details = activeTabDetailLines()
        guard !details.isEmpty else { return nil }
        return details.joined(separator: "\n")
    }

    public func uiStateText() -> String {
        var lines = ["Selected tab: \(selectedTabName)"]
        if let activeTabDetailText = activeTabDetailText() {
            lines.append(activeTabDetailText)
        }
        return lines.joined(separator: "\n")
    }

    public func chatContextText() -> String {
        var lines = [uiStateText()]
        if shouldIncludeDiffNote {
            lines.append("Note: if the user asks about changes visible in an open diff or asks to make edits, they are likely requesting code modifications to the files shown here.")
        }
        return lines.joined(separator: "\n")
    }

    private var selectedTabName: String {
        selectedTab?.displayName ?? currentTab ?? "unknown"
    }

    private var shouldIncludeDiffNote: Bool {
        switch selectedTab {
        case .plans, .prradar:
            return activeDiffContext != nil
        case .none, .some:
            return false
        }
    }

    private func activeTabDetailLines() -> [String] {
        switch selectedTab {
        case .claudeChain:
            return ["Selected chain: \(selectedChainName ?? "none")"]
        case .plans:
            return planDetailLines()
        case .prradar:
            return diffDetailLines(emptyLabel: "Open diff context: none")
        case .architecture, .evals, .repoExplorer, .skills, .worktrees, .none:
            return []
        }
    }

    private func planDetailLines() -> [String] {
        var lines: [String] = []

        if let planContext = activePlanContext {
            lines.append("Selected plan: \(planContext.planName)")
            lines.append("Plan file path: \(planContext.planFilePath)")
            let completedPhases = planContext.completedPhases.isEmpty
                ? "none"
                : planContext.completedPhases.joined(separator: "; ")
            lines.append("Completed phases: \(completedPhases)")
        } else {
            lines.append("Selected plan: \(selectedPlanName ?? "none")")
        }

        lines.append(contentsOf: diffDetailLines(emptyLabel: "Open diff context: none"))
        return lines
    }

    private func diffDetailLines(emptyLabel: String) -> [String] {
        guard let activeDiffContext else {
            return [emptyLabel]
        }

        var lines: [String] = []
        if activeDiffContext.selectedCommits.isEmpty {
            lines.append("Selected commits: none")
        } else {
            lines.append("Selected commits:")
            for commit in activeDiffContext.selectedCommits {
                lines.append("- \(commit.hash): \(commit.message)")
            }
        }

        lines.append("Selected file: \(activeDiffContext.selectedFilePath ?? "none")")
        let selectedSources = activeDiffContext.selectedSources.isEmpty
            ? "none"
            : activeDiffContext.selectedSources.joined(separator: ", ")
        lines.append("Selected diff sources: \(selectedSources)")
        return lines
    }
}
