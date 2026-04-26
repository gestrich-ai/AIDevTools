import Observation

@Observable @MainActor
final class PRRadarNavigationModel {
    private(set) var selectedTab: PRRadarTab = .prs
    private(set) var selectedPRNumber: Int? = nil

    func selectTab(_ tab: PRRadarTab) {
        selectedTab = tab
    }

    func selectPR(number: Int) {
        selectedTab = .prs
        selectedPRNumber = number
    }

    func clearSelectedPRNumber() {
        selectedPRNumber = nil
    }
}

enum PRRadarTab {
    case prs
    case runs
}
