import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import DataPathsService
import Foundation
import LocalDiffService
import MCPService
import SettingsService

public struct SharedCompositionRoot {
    public let credentialResolver: CredentialResolver
    public let dataPathsService: DataPathsService
    public let evalProviderRegistry: EvalProviderRegistry
    public let gitWorkingDirectoryMonitor: GitWorkingDirectoryMonitor
    public let localDiffService: LocalDiffService
    public let mcpService: MCPService
    public let providerRegistry: ProviderRegistry
    public let settingsService: SettingsService
    
    public static func create() throws -> SharedCompositionRoot {
        let secureSettings = SecureSettingsService()
        // Swallowing intentionally: credential profile enumeration failure is non-fatal — fall back to nil.
        let githubProfileId = (try? secureSettings.listGitHubProfileIds())?.first
        let anthropicProfileId = (try? secureSettings.listAnthropicProfileIds())?.first
        let credentialResolver = CredentialResolver(
            secureSettings: secureSettings,
            githubProfileId: githubProfileId,
            anthropicProfileId: anthropicProfileId
        )
        return try create(credentialResolver: credentialResolver)
    }
    
    public static func create(credentialResolver: CredentialResolver) throws -> SharedCompositionRoot {
        let dataPathsService = try DataPathsService(rootPath: AppPreferences().dataPath() ?? AppPreferences.defaultDataPath)
        try MigrateDataPathsUseCase(dataPathsService: dataPathsService).run()
        let settingsService = try SettingsService(dataPathsService: dataPathsService)
        let sessionsDirectory = try dataPathsService.path(for: .anthropicSessions)
        let prefs = AppPreferences()
        let providerRegistry = buildProviderRegistry(
            anthropicAPIKey: credentialResolver.getAnthropicKey(),
            sessionsDirectory: sessionsDirectory,
            includeCodex: prefs.isCodexEnabled(),
            includeAnthropicAPI: prefs.isAnthropicAPIEnabled()
        )
        let configurableProviders = providerRegistry.providers.compactMap { $0 as? any MCPConfigurable }
        return SharedCompositionRoot(
            credentialResolver: credentialResolver,
            dataPathsService: dataPathsService,
            evalProviderRegistry: buildEvalProviderRegistry(from: providerRegistry),
            gitWorkingDirectoryMonitor: GitWorkingDirectoryMonitor(),
            localDiffService: LocalDiffService(),
            mcpService: MCPService(configurableProviders: configurableProviders),
            providerRegistry: providerRegistry,
            settingsService: settingsService
        )
    }
    
    public static func buildEvalProviderRegistry(from providerRegistry: ProviderRegistry) -> EvalProviderRegistry {
        EvalProviderRegistry.from(providerRegistry)
    }
    
    public static func buildProviderRegistry(credentialResolver: CredentialResolver, sessionsDirectory: URL) -> ProviderRegistry {
        buildProviderRegistry(anthropicAPIKey: credentialResolver.getAnthropicKey(), sessionsDirectory: sessionsDirectory)
    }
    
    public static func buildProviderRegistry(anthropicAPIKey: String?, sessionsDirectory: URL, includeCodex: Bool = true, includeAnthropicAPI: Bool = true) -> ProviderRegistry {
        var providers: [any AIClient] = [ClaudeProvider()]
        if includeCodex {
            providers.append(CodexProvider())
        }
        if includeAnthropicAPI, let key = anthropicAPIKey, !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key), sessionsDirectory: sessionsDirectory))
        }
        return ProviderRegistry(providers: providers)
    }
    
}
