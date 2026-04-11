import Foundation
import MCPService

@MainActor @Observable
final class MCPModel {

    private let settingsModel: SettingsModel
    private let mcpService = MCPService()

    init(settingsModel: SettingsModel) {
        self.settingsModel = settingsModel
    }

    var status: MCPStatus {
        mcpService.resolveStatus(
            bundleURL: Bundle.main.bundleURL,
            repoPath: settingsModel.aiDevToolsRepoPath
        )
    }

    func writeMCPConfigIfNeeded() {
        guard case .ready(let binaryURL, _) = status else { return }
        mcpService.writeMCPConfig(binaryURL: binaryURL)
    }
}
