import Foundation

public struct IPCDiffCommit: Codable, Equatable, Sendable {
    public let hash: String
    public let message: String

    public init(hash: String, message: String) {
        self.hash = hash
        self.message = message
    }
}
