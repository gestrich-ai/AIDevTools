public struct ToolCallSummary: Codable, Sendable, Equatable {
    public var attempted: Int
    public var errored: Int
    public var rejected: Int
    public var succeeded: Int

    public init(attempted: Int = 0, succeeded: Int = 0, rejected: Int = 0, errored: Int = 0) {
        self.attempted = attempted
        self.errored = errored
        self.rejected = rejected
        self.succeeded = succeeded
    }
}
