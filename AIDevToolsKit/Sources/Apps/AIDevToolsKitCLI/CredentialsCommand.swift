import ArgumentParser
import CredentialFeature
import CredentialService
import Foundation

struct CredentialsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "credentials",
        abstract: "Manage credential profiles in the macOS Keychain",
        subcommands: [
            AddCredentialCommand.self,
            ListCredentialsCommand.self,
            RemoveCredentialCommand.self,
            ShowCredentialCommand.self,
        ],
        defaultSubcommand: ListCredentialsCommand.self
    )

    struct AddCredentialCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add or update a credential profile"
        )

        @Argument(help: "Credential profile name")
        var profileId: String

        @Option(name: .long, help: "GitHub personal access token")
        var githubToken: String?

        @Option(name: .long, help: "Anthropic API key")
        var anthropicKey: String?

        @Option(name: .long, help: "GitHub App ID (use with --installation-id and --private-key-path)")
        var appId: String?

        @Option(name: .long, help: "GitHub App installation ID")
        var installationId: String?

        @Option(name: .long, help: "Path to GitHub App private key PEM file")
        var privateKeyPath: String?

        func run() async throws {
            let gitHubAuth = try resolveGitHubAuth()

            guard gitHubAuth != nil || anthropicKey != nil else {
                throw ValidationError("No credentials provided. Use --github-token or --app-id/--installation-id/--private-key-path, and optionally --anthropic-key.")
            }

            let service = SecureSettingsService()
            if let gitHubAuth {
                try SaveGitHubProfileUseCase(settingsService: service).execute(
                    profile: GitHubCredentialProfile(id: profileId, auth: gitHubAuth)
                )
            }
            if let anthropicKey {
                try SaveAnthropicProfileUseCase(settingsService: service).execute(
                    profile: AnthropicCredentialProfile(id: profileId, apiKey: anthropicKey)
                )
            }

            var parts: [String] = []
            switch gitHubAuth {
            case .token: parts.append("GitHub token")
            case .app: parts.append("GitHub App credentials")
            case nil: break
            }
            if anthropicKey != nil { parts.append("Anthropic API key") }
            print("Saved \(parts.joined(separator: " and ")) for profile '\(profileId)'.")
        }

        private func resolveGitHubAuth() throws -> GitHubAuth? {
            let hasToken = githubToken != nil
            let hasAppFields = appId != nil || installationId != nil || privateKeyPath != nil

            if hasToken && hasAppFields {
                throw ValidationError("Cannot use --github-token together with --app-id/--installation-id/--private-key-path. Choose one authentication method.")
            }

            if hasToken {
                return .token(githubToken!)
            }

            if hasAppFields {
                guard let appId else {
                    throw ValidationError("--app-id is required for GitHub App authentication.")
                }
                guard let installationId else {
                    throw ValidationError("--installation-id is required for GitHub App authentication.")
                }
                guard let privateKeyPath else {
                    throw ValidationError("--private-key-path is required for GitHub App authentication.")
                }
                let url = URL(fileURLWithPath: (privateKeyPath as NSString).expandingTildeInPath)
                let pem = try String(contentsOf: url, encoding: .utf8)
                return .app(appId: appId, installationId: installationId, privateKeyPEM: pem)
            }

            return nil
        }
    }

    struct ListCredentialsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List credential profiles stored in the Keychain"
        )

        func run() async throws {
            let service = SecureSettingsService()
            let githubIds = try ListGitHubProfilesUseCase(settingsService: service).execute().map(\.id)
            let anthropicIds = try ListAnthropicProfilesUseCase(settingsService: service).execute().map(\.id)
            let allIds = Set(githubIds + anthropicIds).sorted()

            if allIds.isEmpty {
                print("No credential profiles found.")
                print("Use 'ai-dev-tools-kit credentials add <profile>' to create one.")
                return
            }

            print("Credential profiles:\n")
            for id in allIds {
                print("  \(id)")
            }
        }
    }

    struct RemoveCredentialCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a credential profile from the Keychain"
        )

        @Argument(help: "Credential profile name to remove")
        var profileId: String

        func run() async throws {
            let service = SecureSettingsService()
            let githubIds = try ListGitHubProfilesUseCase(settingsService: service).execute().map(\.id)
            let anthropicIds = try ListAnthropicProfilesUseCase(settingsService: service).execute().map(\.id)
            let allIds = Set(githubIds + anthropicIds)

            guard allIds.contains(profileId) else {
                throw ValidationError("Credential profile '\(profileId)' not found.")
            }

            RemoveGitHubProfileUseCase(settingsService: service).execute(id: profileId)
            RemoveAnthropicProfileUseCase(settingsService: service).execute(id: profileId)
            print("Credential profile '\(profileId)' removed.")
        }
    }

    struct ShowCredentialCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show masked credential status for a profile"
        )

        @Argument(help: "Credential profile name")
        var profileId: String

        func run() async throws {
            let service = SecureSettingsService()
            let githubIds = try ListGitHubProfilesUseCase(settingsService: service).execute().map(\.id)
            let anthropicIds = try ListAnthropicProfilesUseCase(settingsService: service).execute().map(\.id)
            let allIds = Set(githubIds + anthropicIds)

            guard allIds.contains(profileId) else {
                throw ValidationError("Credential profile '\(profileId)' not found.")
            }

            print("Profile: \(profileId)\n")

            switch service.loadGitHubProfile(id: profileId)?.auth {
            case .token(let token):
                print("  GitHub auth:       Token (\(masked(token)))")
            case .app(let appId, _, _):
                print("  GitHub auth:       App (ID: \(masked(appId)))")
            case nil:
                print("  GitHub auth:       not set")
            }

            let anthropicMasked = service.loadAnthropicProfile(id: profileId).map { masked($0.apiKey) } ?? "not set"
            print("  Anthropic API key: \(anthropicMasked)")
        }

        private func masked(_ value: String) -> String {
            guard value.count > 8 else { return "****" }
            return "\(value.prefix(4))...\(value.suffix(4))"
        }
    }
}
