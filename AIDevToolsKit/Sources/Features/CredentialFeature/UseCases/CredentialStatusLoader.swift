import CredentialService

struct CredentialStatusLoader {
    private let settingsService: SecureSettingsService

    init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    func loadAllStatuses() throws -> [CredentialStatus] {
        let githubIds = Set(try settingsService.listGitHubProfileIds())
        let anthropicIds = Set(try settingsService.listAnthropicProfileIds())
        return githubIds.union(anthropicIds).sorted().map { loadStatus(account: $0) }
    }

    func loadStatus(account: String) -> CredentialStatus {
        let gitHubAuth: GitHubAuthStatus
        switch settingsService.loadGitHubProfile(id: account)?.auth {
        case .app: gitHubAuth = .app
        case .token: gitHubAuth = .token
        case nil: gitHubAuth = .none
        }
        let hasAnthropic = settingsService.loadAnthropicProfile(id: account) != nil
        return CredentialStatus(account: account, gitHubAuth: gitHubAuth, hasAnthropicKey: hasAnthropic)
    }
}
