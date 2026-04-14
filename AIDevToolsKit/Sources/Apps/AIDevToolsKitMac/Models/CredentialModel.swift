import CredentialFeature
import CredentialService
import Foundation

@MainActor @Observable
final class CredentialModel {
    private let listAnthropicProfilesUseCase: ListAnthropicProfilesUseCase
    private let listGitHubProfilesUseCase: ListGitHubProfilesUseCase
    private let removeAnthropicProfileUseCase: RemoveAnthropicProfileUseCase
    private let removeGitHubProfileUseCase: RemoveGitHubProfileUseCase
    private let saveAnthropicProfileUseCase: SaveAnthropicProfileUseCase
    private let saveGitHubProfileUseCase: SaveGitHubProfileUseCase

    private(set) var state: ModelState = .loaded([], [])

    var anthropicProfiles: [AnthropicCredentialProfile] {
        guard case .loaded(_, let a) = state else { return [] }
        return a
    }

    var gitHubProfiles: [GitHubCredentialProfile] {
        guard case .loaded(let gh, _) = state else { return [] }
        return gh
    }

    // Bridge for views that still use the combined account concept.
    var credentialAccounts: [CredentialStatus] {
        let ghIds = Set(gitHubProfiles.map(\.id))
        let anthropicIds = Set(anthropicProfiles.map(\.id))
        return ghIds.union(anthropicIds).sorted().map { id in
            let gitHubAuth: GitHubAuthStatus
            switch gitHubProfiles.first(where: { $0.id == id })?.auth {
            case .app: gitHubAuth = .app
            case .token: gitHubAuth = .token
            case nil: gitHubAuth = .none
            }
            let hasAnthropicKey = anthropicProfiles.contains(where: { $0.id == id })
            return CredentialStatus(account: id, gitHubAuth: gitHubAuth, hasAnthropicKey: hasAnthropicKey)
        }
    }

    init(
        listAnthropicProfilesUseCase: ListAnthropicProfilesUseCase,
        listGitHubProfilesUseCase: ListGitHubProfilesUseCase,
        removeAnthropicProfileUseCase: RemoveAnthropicProfileUseCase,
        removeGitHubProfileUseCase: RemoveGitHubProfileUseCase,
        saveAnthropicProfileUseCase: SaveAnthropicProfileUseCase,
        saveGitHubProfileUseCase: SaveGitHubProfileUseCase
    ) {
        self.listAnthropicProfilesUseCase = listAnthropicProfilesUseCase
        self.listGitHubProfilesUseCase = listGitHubProfilesUseCase
        self.removeAnthropicProfileUseCase = removeAnthropicProfileUseCase
        self.removeGitHubProfileUseCase = removeGitHubProfileUseCase
        self.saveAnthropicProfileUseCase = saveAnthropicProfileUseCase
        self.saveGitHubProfileUseCase = saveGitHubProfileUseCase
        reload()
    }

    convenience init() {
        let service = SecureSettingsService()
        self.init(
            listAnthropicProfilesUseCase: ListAnthropicProfilesUseCase(settingsService: service),
            listGitHubProfilesUseCase: ListGitHubProfilesUseCase(settingsService: service),
            removeAnthropicProfileUseCase: RemoveAnthropicProfileUseCase(settingsService: service),
            removeGitHubProfileUseCase: RemoveGitHubProfileUseCase(settingsService: service),
            saveAnthropicProfileUseCase: SaveAnthropicProfileUseCase(settingsService: service),
            saveGitHubProfileUseCase: SaveGitHubProfileUseCase(settingsService: service)
        )
    }

    func saveCredentials(account: String, gitHubAuth: GitHubAuth?, anthropicKey: String?) throws {
        if let gitHubAuth {
            try saveGitHubProfileUseCase.execute(profile: GitHubCredentialProfile(id: account, auth: gitHubAuth))
        }
        if let anthropicKey, !anthropicKey.isEmpty {
            try saveAnthropicProfileUseCase.execute(profile: AnthropicCredentialProfile(id: account, apiKey: anthropicKey))
        }
        reload()
    }

    func removeCredentials(account: String) throws {
        removeGitHubProfileUseCase.execute(id: account)
        removeAnthropicProfileUseCase.execute(id: account)
        reload()
    }

    private func reload() {
        do {
            let gh = try listGitHubProfilesUseCase.execute()
            let a = try listAnthropicProfilesUseCase.execute()
            state = .loaded(gh, a)
        } catch {
            state = .error(error)
        }
    }

    enum ModelState {
        case loaded([GitHubCredentialProfile], [AnthropicCredentialProfile])
        case error(Error)
    }
}
