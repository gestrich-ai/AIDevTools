import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import Foundation
import ProviderRegistryService

func makeProviderRegistry() -> ProviderRegistry {
    var providers: [any AIClient] = [
        ClaudeProvider(),
        CodexProvider(),
    ]
    if let client = makeAnthropicClientIfAvailable() {
        providers.append(client)
    }
    return ProviderRegistry(providers: providers)
}

func makeEvalRegistry(debug: Bool = false) -> EvalProviderRegistry {
    EvalProviderRegistry(entries: [
        EvalProviderEntry(client: ClaudeProvider()),
        EvalProviderEntry(client: CodexProvider()),
    ])
}

func makeAnthropicClientIfAvailable() -> AnthropicProvider? {
    guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
        return nil
    }
    return AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key))
}
