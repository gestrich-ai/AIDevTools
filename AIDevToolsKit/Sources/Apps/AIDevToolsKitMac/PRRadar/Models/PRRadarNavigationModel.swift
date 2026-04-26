import Observation

@Observable @MainActor
final class PRRadarNavigationModel {
    var selectedTab: PRRadarTab = .prs
    var selectedPRNumber: Int? = nil
}

enum PRRadarTab {
    case prs
    case runs
}
