import CredentialService

struct CredentialStatusLoader {
    private let settingsService: CredentialSettingsService

    init(settingsService: CredentialSettingsService) {
        self.settingsService = settingsService
    }

    func loadAllStatuses() throws -> [CredentialStatus] {
        try settingsService.listCredentialAccounts().map { account in
            loadStatus(account: account)
        }
    }

    func loadStatus(account: String) -> CredentialStatus {
        let gitHubAuth: GitHubAuthStatus
        switch settingsService.loadGitHubAuth(account: account) {
        case .app: gitHubAuth = .app
        case .token: gitHubAuth = .token
        case nil: gitHubAuth = .none
        }
        let hasAnthropic = (try? settingsService.loadAnthropicKey(account: account)) != nil
        return CredentialStatus(account: account, gitHubAuth: gitHubAuth, hasAnthropicKey: hasAnthropic)
    }
}
