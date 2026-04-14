import Foundation

public struct AnthropicCredentialProfile: Identifiable, Sendable {
    public let id: String
    public let apiKey: String

    public init(id: String, apiKey: String) {
        self.id = id
        self.apiKey = apiKey
    }
}
