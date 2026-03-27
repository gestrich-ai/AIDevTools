public protocol StreamFormatter: Sendable {
    func format(_ rawChunk: String) -> String
}
