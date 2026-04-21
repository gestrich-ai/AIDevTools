import CredentialService
import DataPathsService
import Foundation
import GitSDK
import LocalDiffService
import MCPService
import ProviderRegistryService
import RepoExplorerFeature
import SettingsService

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalProviderRegistry: EvalProviderRegistry
    let gitClientFactory: @Sendable (String?) -> GitClient
    let gitWorkingDirectoryMonitor: GitWorkingDirectoryMonitor
    let localDiffService: LocalDiffService
    let mcpModel: MCPModel
    let providerModel: ProviderModel
    let repoExplorerViewModelFactory: @MainActor () -> DirectoryBrowserViewModel
    let settingsModel: SettingsModel
    let settingsService: SettingsService
    
    static func create() throws -> CompositionRoot {
        let shared = try SharedCompositionRoot.create()
        let settingsModel = try SettingsModel(settingsService: shared.settingsService)
        
        let gitClientFactory: @Sendable (String?) -> GitClient = { profileId in
            guard let profileId else { return GitClient() }
            let resolver = CredentialResolver(
                secureSettings: SecureSettingsService(),
                githubProfileId: profileId,
                anthropicProfileId: nil
            )
            guard case .token(let token) = resolver.getGitHubAuth() else { return GitClient() }
            setenv("GH_TOKEN", token, 1)
            return GitClient(environment: ["GH_TOKEN": token])
        }
        
        let sessionsDirectory = try shared.dataPathsService.path(for: .anthropicSessions)
        let mcpModel = MCPModel(settingsModel: settingsModel, mcpService: shared.mcpService)
        mcpModel.writeMCPConfigIfNeeded()
        
        let providerModel = ProviderModel(registrySource: {
            let secureSettings = SecureSettingsService()
            // Swallowing intentionally: credential profile enumeration failure is non-fatal — fall back to nil.
            let githubProfileId = (try? secureSettings.listGitHubProfileIds())?.first
            let anthropicProfileId = (try? secureSettings.listAnthropicProfileIds())?.first
            let resolver = CredentialResolver(
                secureSettings: secureSettings,
                githubProfileId: githubProfileId,
                anthropicProfileId: anthropicProfileId
            )
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
            gitWorkingDirectoryMonitor: shared.gitWorkingDirectoryMonitor,
            localDiffService: shared.localDiffService,
            mcpModel: mcpModel,
            providerModel: providerModel,
            repoExplorerViewModelFactory: makeRepoExplorerViewModelFactory(dataPathsService: shared.dataPathsService),
            settingsModel: settingsModel,
            settingsService: shared.settingsService
        )
    }
    
}
