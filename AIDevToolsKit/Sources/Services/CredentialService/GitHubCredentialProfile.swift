import Foundation

public struct GitHubCredentialProfile: Identifiable, Sendable {
    public let id: String
    public let auth: GitHubAuth

    public init(id: String, auth: GitHubAuth) {
        self.id = id
        self.auth = auth
    }
}
