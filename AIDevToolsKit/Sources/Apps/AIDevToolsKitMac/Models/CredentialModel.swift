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

    func saveGitHubProfile(id: String, auth: GitHubAuth) throws {
        try saveGitHubProfileUseCase.execute(profile: GitHubCredentialProfile(id: id, auth: auth))
        reload()
    }

    func removeGitHubProfile(id: String) {
        removeGitHubProfileUseCase.execute(id: id)
        reload()
    }

    func saveAnthropicProfile(id: String, apiKey: String) throws {
        try saveAnthropicProfileUseCase.execute(profile: AnthropicCredentialProfile(id: id, apiKey: apiKey))
        reload()
    }

    func removeAnthropicProfile(id: String) {
        removeAnthropicProfileUseCase.execute(id: id)
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
