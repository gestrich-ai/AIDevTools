import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import Foundation
import ProviderRegistryService

@MainActor @Observable
final class ProviderModel {
    private(set) var providerRegistry: ProviderRegistry
    private let anthropicAPIKeySource: @Sendable () -> String?

    init(anthropicAPIKeySource: @escaping @Sendable () -> String? = {
        UserDefaults.standard.string(forKey: "anthropicAPIKey")
    }) {
        self.anthropicAPIKeySource = anthropicAPIKeySource
        self.providerRegistry = Self.buildRegistry(anthropicAPIKey: anthropicAPIKeySource())
    }

    func refreshProviders() {
        self.providerRegistry = Self.buildRegistry(anthropicAPIKey: anthropicAPIKeySource())
    }

    private static func buildRegistry(anthropicAPIKey: String?) -> ProviderRegistry {
        var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
        if let key = anthropicAPIKey, !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key)))
        }
        return ProviderRegistry(providers: providers)
    }
}
