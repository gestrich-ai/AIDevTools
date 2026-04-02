import Foundation

public struct AIMetrics: Sendable {
    public let cost: Double?
    public let duration: TimeInterval?
    public let turns: Int?

    public init(cost: Double?, duration: TimeInterval?, turns: Int?) {
        self.cost = cost
        self.duration = duration
        self.turns = turns
    }
}
