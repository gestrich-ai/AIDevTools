public enum ExecutePipelineProgress: Sendable {
    case stepStarted(stepDescription: String, index: Int, total: Int)
    case stepOutput(text: String)
    case stepCompleted(stepDescription: String, index: Int)
    case stepsAppended(count: Int)
    case allCompleted(stepsExecuted: Int)
}