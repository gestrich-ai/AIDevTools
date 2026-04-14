import ArgumentParser
import CredentialFeature
import CredentialService
import Foundation

struct CredentialsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "credentials",
        abstract: "Manage credential profiles in the macOS Keychain",
        subcommands: [
            AnthropicCommand.self,
            GitHubCommand.self,
        ]
    )

    struct AnthropicCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "anthropic",
            abstract: "Manage Anthropic credential profiles",
            subcommands: [
                AddCommand.self,
                ListCommand.self,
                RemoveCommand.self,
                ShowCommand.self,
            ],
            defaultSubcommand: ListCommand.self
        )

        struct AddCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "add",
                abstract: "Add or update an Anthropic credential profile"
            )

            @Argument(help: "Profile name")
            var profileId: String

            @Option(name: .long, help: "Anthropic API key")
            var apiKey: String

            func run() async throws {
                let service = SecureSettingsService()
                try SaveAnthropicProfileUseCase(settingsService: service).execute(
                    profile: AnthropicCredentialProfile(id: profileId, apiKey: apiKey)
                )
                print("Saved Anthropic API key for profile '\(profileId)'.")
            }
        }

        struct ListCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List Anthropic credential profiles"
            )

            func run() async throws {
                let service = SecureSettingsService()
                let profiles = try ListAnthropicProfilesUseCase(settingsService: service).execute()

                if profiles.isEmpty {
                    print("No Anthropic credential profiles found.")
                    print("Use 'credentials anthropic add <profile> --api-key <key>' to create one.")
                    return
                }

                print("Anthropic credential profiles:\n")
                for profile in profiles.sorted(by: { $0.id < $1.id }) {
                    print("  \(profile.id)")
                }
            }
        }

        struct RemoveCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "remove",
                abstract: "Remove an Anthropic credential profile"
            )

            @Argument(help: "Profile name")
            var profileId: String

            func run() async throws {
                let service = SecureSettingsService()
                let ids = try ListAnthropicProfilesUseCase(settingsService: service).execute().map(\.id)

                guard ids.contains(profileId) else {
                    throw ValidationError("Anthropic credential profile '\(profileId)' not found.")
                }

                RemoveAnthropicProfileUseCase(settingsService: service).execute(id: profileId)
                print("Anthropic credential profile '\(profileId)' removed.")
            }
        }

        struct ShowCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "show",
                abstract: "Show masked credentials for an Anthropic profile"
            )

            @Argument(help: "Profile name")
            var profileId: String

            func run() async throws {
                let service = SecureSettingsService()
                guard let profile = service.loadAnthropicProfile(id: profileId) else {
                    throw ValidationError("Anthropic credential profile '\(profileId)' not found.")
                }

                print("Anthropic profile: \(profile.id)\n")
                print("  API key: \(masked(profile.apiKey))")
            }

            private func masked(_ value: String) -> String {
                guard value.count > 8 else { return "****" }
                return "\(value.prefix(4))...\(value.suffix(4))"
            }
        }
    }

    struct GitHubCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "github",
            abstract: "Manage GitHub credential profiles",
            subcommands: [
                AddCommand.self,
                ListCommand.self,
                RemoveCommand.self,
                ShowCommand.self,
            ],
            defaultSubcommand: ListCommand.self
        )

        struct AddCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "add",
                abstract: "Add or update a GitHub credential profile"
            )

            @Argument(help: "Profile name")
            var profileId: String

            @Option(name: .long, help: "Personal access token")
            var token: String?

            @Option(name: .long, help: "GitHub App ID")
            var appId: String?

            @Option(name: .long, help: "GitHub App installation ID")
            var installationId: String?

            @Option(name: .long, help: "Path to GitHub App private key PEM file")
            var privateKeyPath: String?

            func run() async throws {
                let auth = try resolveAuth()
                let service = SecureSettingsService()
                try SaveGitHubProfileUseCase(settingsService: service).execute(
                    profile: GitHubCredentialProfile(id: profileId, auth: auth)
                )
                switch auth {
                case .token:
                    print("Saved GitHub token profile '\(profileId)'.")
                case .app:
                    print("Saved GitHub App profile '\(profileId)'.")
                }
            }

            private func resolveAuth() throws -> GitHubAuth {
                let hasToken = token != nil
                let hasAppFields = appId != nil || installationId != nil || privateKeyPath != nil

                if hasToken && hasAppFields {
                    throw ValidationError("Cannot use --token together with --app-id/--installation-id/--private-key-path. Choose one authentication method.")
                }

                if let token {
                    return .token(token)
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

                throw ValidationError("Provide --token for a personal access token, or --app-id/--installation-id/--private-key-path for a GitHub App.")
            }
        }

        struct ListCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List GitHub credential profiles"
            )

            func run() async throws {
                let service = SecureSettingsService()
                let profiles = try ListGitHubProfilesUseCase(settingsService: service).execute()

                if profiles.isEmpty {
                    print("No GitHub credential profiles found.")
                    print("Use 'credentials github add <profile> --token <token>' to create one.")
                    return
                }

                print("GitHub credential profiles:\n")
                for profile in profiles.sorted(by: { $0.id < $1.id }) {
                    switch profile.auth {
                    case .token:
                        print("  \(profile.id)  (token)")
                    case .app(let appId, _, _):
                        print("  \(profile.id)  (app: \(appId))")
                    }
                }
            }
        }

        struct RemoveCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "remove",
                abstract: "Remove a GitHub credential profile"
            )

            @Argument(help: "Profile name")
            var profileId: String

            func run() async throws {
                let service = SecureSettingsService()
                let ids = try ListGitHubProfilesUseCase(settingsService: service).execute().map(\.id)

                guard ids.contains(profileId) else {
                    throw ValidationError("GitHub credential profile '\(profileId)' not found.")
                }

                RemoveGitHubProfileUseCase(settingsService: service).execute(id: profileId)
                print("GitHub credential profile '\(profileId)' removed.")
            }
        }

        struct ShowCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "show",
                abstract: "Show masked credentials for a GitHub profile"
            )

            @Argument(help: "Profile name")
            var profileId: String

            func run() async throws {
                let service = SecureSettingsService()
                guard let profile = service.loadGitHubProfile(id: profileId) else {
                    throw ValidationError("GitHub credential profile '\(profileId)' not found.")
                }

                print("GitHub profile: \(profile.id)\n")
                switch profile.auth {
                case .token(let token):
                    print("  Auth type: token")
                    print("  Token:     \(masked(token))")
                case .app(let appId, let installationId, let pem):
                    print("  Auth type:       app")
                    print("  App ID:          \(masked(appId))")
                    print("  Installation ID: \(masked(installationId))")
                    print("  Private key:     \(masked(pem))")
                }
            }

            private func masked(_ value: String) -> String {
                guard value.count > 8 else { return "****" }
                return "\(value.prefix(4))...\(value.suffix(4))"
            }
        }
    }
}
