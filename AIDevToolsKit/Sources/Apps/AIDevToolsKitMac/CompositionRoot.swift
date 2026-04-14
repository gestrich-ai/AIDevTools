import CredentialService
import DataPathsService
import Foundation
import GitSDK
import ProviderRegistryService
import SettingsService

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalProviderRegistry: EvalProviderRegistry
    let gitClientFactory: @Sendable (String?) -> GitClient
    let mcpModel: MCPModel
    let providerModel: ProviderModel
    let settingsModel: SettingsModel
    let settingsService: SettingsService

    static func create() throws -> CompositionRoot {
        let shared = try SharedCompositionRoot.create()
        let settingsModel = SettingsModel()

        let gitClientFactory: @Sendable (String?) -> GitClient = { account in
            guard let account else { return GitClient() }
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: account
            )
            guard case .token(let token) = resolver.getGitHubAuth() else { return GitClient() }
            setenv("GH_TOKEN", token, 1)
            return GitClient(environment: ["GH_TOKEN": token])
        }

        let sessionsDirectory = try shared.dataPathsService.path(for: .anthropicSessions)
        let mcpModel = MCPModel(settingsModel: settingsModel)
        mcpModel.writeMCPConfigIfNeeded()

        let providerModel = ProviderModel(registrySource: {
            let secureSettings = SecureSettingsService()
            let account = (try? secureSettings.listGitHubProfileIds())?.first ?? "default"
            let resolver = CredentialResolver(settingsService: secureSettings, githubAccount: account)
            return SharedCompositionRoot.buildProviderRegistry(
                anthropicAPIKey: resolver.getAnthropicKey(),
                sessionsDirectory: sessionsDirectory,
                includeCodex: AppPreferences().isCodexEnabled(),
                includeAnthropicAPI: AppPreferences().isAnthropicAPIEnabled()
            )
        })

        return CompositionRoot(
            dataPathsService: shared.dataPathsService,
            evalProviderRegistry: shared.evalProviderRegistry,
            gitClientFactory: gitClientFactory,
            mcpModel: mcpModel,
            providerModel: providerModel,
            settingsModel: settingsModel,
            settingsService: shared.settingsService
        )
    }

}
