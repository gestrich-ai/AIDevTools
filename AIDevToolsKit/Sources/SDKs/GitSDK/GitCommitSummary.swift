import Foundation

public struct GitCommitSummary: Equatable, Sendable {
    public let body: String
    public let hash: String
    public let subject: String

    public init(body: String, hash: String, subject: String) {
        self.body = body
        self.hash = hash
        self.subject = subject
    }
}
