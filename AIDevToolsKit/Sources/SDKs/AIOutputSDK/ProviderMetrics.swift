public struct ProviderMetrics: Sendable {
    public var costUsd: Double?
    public var durationMs: Int?
    public var turns: Int?

    public init(
        durationMs: Int? = nil,
        costUsd: Double? = nil,
        turns: Int? = nil
    ) {
        self.costUsd = costUsd
        self.durationMs = durationMs
        self.turns = turns
    }
}
