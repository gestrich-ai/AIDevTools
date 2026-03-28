import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import Foundation
import ProviderRegistryService

@MainActor @Observable
final class ProviderModel {
    private(set) var providerRegistry: ProviderRegistry

    init() {
        self.providerRegistry = Self.buildRegistry()
    }

    func refreshProviders() {
        self.providerRegistry = Self.buildRegistry()
    }

    private static func buildRegistry() -> ProviderRegistry {
        var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
        if let key = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key)))
        }
        return ProviderRegistry(providers: providers)
    }
}
