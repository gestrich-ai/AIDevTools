public struct ProviderCapabilities: Sendable {
    public var supportsEventStream: Bool
    public var supportsMetrics: Bool
    public var supportsToolEventAssertions: Bool

    public init(
        supportsToolEventAssertions: Bool = true,
        supportsEventStream: Bool = true,
        supportsMetrics: Bool = false
    ) {
        self.supportsEventStream = supportsEventStream
        self.supportsMetrics = supportsMetrics
        self.supportsToolEventAssertions = supportsToolEventAssertions
    }
}
