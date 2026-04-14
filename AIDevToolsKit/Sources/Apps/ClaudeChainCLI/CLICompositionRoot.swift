import CredentialService
import Foundation
import GitSDK
import ProviderRegistryService

struct CLICompositionRoot {
    let credentialResolver: CredentialResolver
    let evalProviderRegistry: EvalProviderRegistry
    let gitClient: GitClient
    let providerRegistry: ProviderRegistry

    static func create() throws -> CLICompositionRoot {
        let shared = try SharedCompositionRoot.create()
        return CLICompositionRoot(shared: shared)
    }

    static func create(githubProfileId: String?, anthropicProfileId: String? = nil, githubToken: String? = nil) throws -> CLICompositionRoot {
        let secureSettings = SecureSettingsService()
        let resolver: CredentialResolver
        if let githubToken {
            resolver = CredentialResolver.withExplicitToken(githubToken)
        } else {
            // Swallowing intentionally: profile enumeration failure is non-fatal — fall back to nil.
            let profileId = githubProfileId ?? (try? secureSettings.listGitHubProfileIds())?.first
            resolver = CredentialResolver(secureSettings: secureSettings, githubProfileId: profileId, anthropicProfileId: anthropicProfileId)
        }
        if case .token(let token) = resolver.getGitHubAuth() {
            setenv("GH_TOKEN", token, 1)
        }
        let shared = try SharedCompositionRoot.create(credentialResolver: resolver)
        return CLICompositionRoot(shared: shared)
    }

    private init(shared: SharedCompositionRoot) {
        self.credentialResolver = shared.credentialResolver
        self.evalProviderRegistry = shared.evalProviderRegistry
        self.gitClient = GitClient(environment: shared.credentialResolver.gitEnvironment)
        self.providerRegistry = shared.providerRegistry
    }
}
