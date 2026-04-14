import CredentialFeature
import CredentialService
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

    static func create(githubProfileId: String?, githubToken: String? = nil) throws -> CLICompositionRoot {
        let resolver = resolveGitHubCredentials(githubProfileId: githubProfileId, githubToken: githubToken)
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
