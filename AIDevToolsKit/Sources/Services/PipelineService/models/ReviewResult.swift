public struct ReviewResult: Decodable, Sendable {
    public let fixes: [Fix]

    public struct Fix: Decodable, Sendable {
        public let description: String
        public let prompt: String
    }
}