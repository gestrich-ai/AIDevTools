import DataPathsService
import Foundation
import Observation

@Observable
final class ExperimentalSettings {
    static let architecturePlannerKey = "experimental.architecturePlanner"

    var isAnthropicAPIEnabled: Bool
    var isArchitecturePlannerEnabled: Bool
    var isCodexEnabled: Bool

    init() {
        let prefs = AppPreferences()
        self.isAnthropicAPIEnabled = prefs.isAnthropicAPIEnabled()
        self.isArchitecturePlannerEnabled = UserDefaults.standard.object(forKey: Self.architecturePlannerKey) as? Bool ?? false
        self.isCodexEnabled = prefs.isCodexEnabled()
    }

    func updateAnthropicAPIEnabled(_ enabled: Bool) {
        isAnthropicAPIEnabled = enabled
        AppPreferences().setAnthropicAPIEnabled(enabled)
    }

    func updateArchitecturePlannerEnabled(_ enabled: Bool) {
        isArchitecturePlannerEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.architecturePlannerKey)
    }

    func updateCodexEnabled(_ enabled: Bool) {
        isCodexEnabled = enabled
        AppPreferences().setCodexEnabled(enabled)
    }
}
