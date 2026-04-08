import Foundation

public enum CredentialError: Error, LocalizedError {
    case notConfigured(account: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let account):
            let accountDesc = account.isEmpty ? "an unnamed account" : "account '\(account)'"
            return "GitHub credentials are not configured for \(accountDesc). Add credentials via the Mac app or set GITHUB_TOKEN in your environment."
        }
    }
}
