public struct Provider: RawRepresentable, Codable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }
}

extension Provider {
    public init(client: any AIClient) {
        self.init(rawValue: client.name)
    }
}
