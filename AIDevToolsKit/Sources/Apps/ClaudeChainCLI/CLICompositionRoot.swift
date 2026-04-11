import CredentialService
import ProviderRegistryService

struct CLICompositionRoot {
    let evalProviderRegistry: EvalProviderRegistry
    let providerRegistry: ProviderRegistry

    static func create() throws -> CLICompositionRoot {
        let shared = try SharedCompositionRoot.create()
        return CLICompositionRoot(
            evalProviderRegistry: shared.evalProviderRegistry,
            providerRegistry: shared.providerRegistry
        )
    }

    static func create(credentialResolver: CredentialResolver) throws -> CLICompositionRoot {
        let shared = try SharedCompositionRoot.create(credentialResolver: credentialResolver)
        return CLICompositionRoot(
            evalProviderRegistry: shared.evalProviderRegistry,
            providerRegistry: shared.providerRegistry
        )
    }
}
