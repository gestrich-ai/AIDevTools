public struct ProviderError: Sendable {
    public let message: String
    public var details: [String: JSONValue]?
    public var subtype: String?

    public init(
        message: String,
        subtype: String? = nil,
        details: [String: JSONValue]? = nil
    ) {
        self.message = message
        self.details = details
        self.subtype = subtype
    }
}
