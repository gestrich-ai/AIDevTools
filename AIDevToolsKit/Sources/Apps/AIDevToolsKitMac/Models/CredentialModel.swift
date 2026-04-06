import CredentialFeature
import CredentialService
import Foundation

@MainActor @Observable
final class CredentialModel {

    private let listCredentialStatusesUseCase: ListCredentialStatusesUseCase
    private let removeCredentialsUseCase: RemoveCredentialsUseCase
    private let saveCredentialsUseCase: SaveCredentialsUseCase

    private(set) var state: ModelState = .loaded([])

    var credentialAccounts: [CredentialStatus] {
        if case .loaded(let accounts) = state { return accounts }
        return []
    }

    init(
        listCredentialStatusesUseCase: ListCredentialStatusesUseCase,
        removeCredentialsUseCase: RemoveCredentialsUseCase,
        saveCredentialsUseCase: SaveCredentialsUseCase
    ) {
        self.listCredentialStatusesUseCase = listCredentialStatusesUseCase
        self.removeCredentialsUseCase = removeCredentialsUseCase
        self.saveCredentialsUseCase = saveCredentialsUseCase
        do {
            self.state = .loaded(try listCredentialStatusesUseCase.execute())
        } catch {
            self.state = .error(error)
        }
    }

    convenience init() {
        let service = SecureSettingsService()
        self.init(
            listCredentialStatusesUseCase: ListCredentialStatusesUseCase(settingsService: service),
            removeCredentialsUseCase: RemoveCredentialsUseCase(settingsService: service),
            saveCredentialsUseCase: SaveCredentialsUseCase(settingsService: service)
        )
    }

    func saveCredentials(account: String, gitHubAuth: GitHubAuth?, anthropicKey: String?) throws {
        state = .loaded(try saveCredentialsUseCase.execute(
            account: account, gitHubAuth: gitHubAuth, anthropicKey: anthropicKey
        ))
    }

    func removeCredentials(account: String) throws {
        state = .loaded(try removeCredentialsUseCase.execute(account: account))
    }

    enum ModelState {
        case loaded([CredentialStatus])
        case error(Error)
    }
}
