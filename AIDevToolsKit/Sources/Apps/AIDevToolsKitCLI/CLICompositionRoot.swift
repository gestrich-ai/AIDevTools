import CredentialFeature
import CredentialService
import ProviderRegistryService

struct CLICompositionRoot {
    let credentialResolver: CredentialResolver
    let evalProviderRegistry: EvalProviderRegistry
    let providerRegistry: ProviderRegistry

    static func create() throws -> CLICompositionRoot {
        let shared = try SharedCompositionRoot.create()
        return CLICompositionRoot(
            credentialResolver: shared.credentialResolver,
            evalProviderRegistry: shared.evalProviderRegistry,
            providerRegistry: shared.providerRegistry
        )
    }

    static func create(githubAccount: String?, githubToken: String? = nil) throws -> CLICompositionRoot {
        let resolver = resolveGitHubCredentials(githubAccount: githubAccount, githubToken: githubToken)
        let shared = try SharedCompositionRoot.create(credentialResolver: resolver)
        return CLICompositionRoot(
            credentialResolver: shared.credentialResolver,
            evalProviderRegistry: shared.evalProviderRegistry,
            providerRegistry: shared.providerRegistry
        )
    }
}
