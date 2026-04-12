import Foundation

public struct AuthorCacheEntry: Codable, Sendable {
    public let login: String
    public let name: String
    public let avatarURL: String?
    public let fetchedAt: String

    public init(login: String, name: String, avatarURL: String? = nil, fetchedAt: String) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.fetchedAt = fetchedAt
    }
}

public struct AuthorCache: Codable, Sendable {
    public var entries: [String: AuthorCacheEntry]

    public init(entries: [String: AuthorCacheEntry] = [:]) {
        self.entries = entries
    }
}
