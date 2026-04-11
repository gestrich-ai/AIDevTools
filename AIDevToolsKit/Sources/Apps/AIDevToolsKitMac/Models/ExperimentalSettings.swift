import Foundation
import Observation

@Observable
final class ExperimentalSettings {
    var isArchitecturePlannerEnabled: Bool {
        didSet { UserDefaults.standard.set(isArchitecturePlannerEnabled, forKey: "experimental.architecturePlanner") }
    }

    init() {
        self.isArchitecturePlannerEnabled = UserDefaults.standard.object(forKey: "experimental.architecturePlanner") as? Bool ?? false
    }
}
