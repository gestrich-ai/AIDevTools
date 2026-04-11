import CredentialService
import ProviderRegistryService

struct CLICompositionRoot {
    let shared: SharedCompositionRoot

    static func create() throws -> CLICompositionRoot {
        CLICompositionRoot(shared: try SharedCompositionRoot.create())
    }

    static func create(credentialResolver: CredentialResolver) throws -> CLICompositionRoot {
        CLICompositionRoot(shared: try SharedCompositionRoot.create(credentialResolver: credentialResolver))
    }
}
