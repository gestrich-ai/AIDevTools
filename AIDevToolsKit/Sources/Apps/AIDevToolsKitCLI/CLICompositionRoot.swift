import CredentialFeature
import CredentialService
import EnvironmentSDK
import GitSDK
import Logging
import LoggingSDK
import MCPService
import ProviderRegistryService

struct CLICompositionRoot {
    let credentialResolver: CredentialResolver
    let dotEnvLoader: DotEnvironmentLoader
    let evalProviderRegistry: EvalProviderRegistry
    let gitClient: GitClient
    let mcpService: MCPService
    let providerRegistry: ProviderRegistry

    static func preServiceSetup(logLevel: Logger.Level) {
        AIDevToolsLogging.bootstrap(logLevel: logLevel)
        DotEnvironmentLoader().applyToEnvironment()
    }

    static func create() throws -> CLICompositionRoot {
        let shared = try SharedCompositionRoot.create()
        return CLICompositionRoot(shared: shared)
    }

    static func create(githubAccount: String?, githubToken: String? = nil, printGitOutput: Bool = true) throws -> CLICompositionRoot {
        let resolver = resolveGitHubCredentials(githubAccount: githubAccount, githubToken: githubToken)
        let shared = try SharedCompositionRoot.create(credentialResolver: resolver)
        return CLICompositionRoot(shared: shared, printGitOutput: printGitOutput)
    }

    private init(shared: SharedCompositionRoot, printGitOutput: Bool = true) {
        credentialResolver = shared.credentialResolver
        dotEnvLoader = DotEnvironmentLoader()
        evalProviderRegistry = shared.evalProviderRegistry
        gitClient = GitClient(printOutput: printGitOutput, environment: shared.credentialResolver.gitEnvironment)
        mcpService = MCPService()
        providerRegistry = shared.providerRegistry
        postServiceSetup()
    }

    private func postServiceSetup() {
        mcpService.writeMCPConfigFromCurrentProcess()
    }
}
