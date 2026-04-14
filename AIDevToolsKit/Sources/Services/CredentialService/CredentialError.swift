import Foundation

public enum CredentialError: Error, LocalizedError {
    case notConfigured(profileId: String?)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let profileId):
            let profileDesc = profileId.map { "profile '\($0)'" } ?? "an unconfigured profile"
            return "GitHub credentials are not configured for \(profileDesc). Add credentials via the Mac app or set GITHUB_TOKEN in your environment."
        }
    }
}
