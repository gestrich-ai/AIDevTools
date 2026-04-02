public enum PipelineError: Error, Sendable {
    case cancelled
    case capacityExceeded(openCount: Int, maxOpen: Int)
    case missingContextValue(key: String)
    case outputTypeMismatch(expected: String, received: String)
}
