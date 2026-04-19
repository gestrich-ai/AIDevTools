import Foundation

/// Request envelope sent from the CLI to the Mac app over IPC.
public struct IPCRequest: Codable, Sendable {
    public let query: String

    public init(query: String) {
        self.query = query
    }
}
