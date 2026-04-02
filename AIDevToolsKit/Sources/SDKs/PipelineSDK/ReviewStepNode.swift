public struct ReviewStep: PipelineNode {
    public let displayName: String
    public let id: String

    public init(id: String, displayName: String) {
        self.displayName = displayName
        self.id = id
    }

    // Pipeline handles this node type specially via type cast — it stores a
    // CheckedContinuation and waits for approve() or cancel() to be called.
    // This passthrough implementation exists only to satisfy the protocol.
    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        return context
    }
}
