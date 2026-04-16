import CredentialService
import EnvironmentSDK
import Foundation
import GitSDK
import Logging
import LoggingSDK
import MCPService
import ProviderRegistryService

struct CLICompositionRoot {
    let credentialResolver: CredentialResolver
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

    static func create(githubProfileId: String?, anthropicProfileId: String? = nil, githubToken: String? = nil, printGitOutput: Bool = true) throws -> CLICompositionRoot {
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
        return CLICompositionRoot(shared: shared, printGitOutput: printGitOutput)
    }

    private init(shared: SharedCompositionRoot, printGitOutput: Bool = true) {
        credentialResolver = shared.credentialResolver
        evalProviderRegistry = shared.evalProviderRegistry
        gitClient = GitClient(printOutput: printGitOutput, environment: shared.credentialResolver.gitEnvironment)
        mcpService = shared.mcpService
        providerRegistry = shared.providerRegistry
        postServiceSetup()
    }

    private func postServiceSetup() {
        mcpService.writeMCPConfigFromCurrentProcess()
    }
}
