public struct ExecutePipelineResult: Sendable {
    public let stepsExecuted: Int
    public let allCompleted: Bool

    public init(stepsExecuted: Int, allCompleted: Bool) {
        self.stepsExecuted = stepsExecuted
        self.allCompleted = allCompleted
    }
}