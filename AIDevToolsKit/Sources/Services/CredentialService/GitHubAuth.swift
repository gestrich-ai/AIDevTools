import Foundation

public enum GitHubAuth: Sendable {
    case app(appId: String, installationId: String, privateKeyPEM: String)
    case token(String)
}
