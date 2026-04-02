public struct ReviewStep: PipelineNode {
    public let displayName: String
    public let id: String

    public init(id: String, displayName: String) {
        self.displayName = displayName
        self.id = id
    }

    // PipelineRunner handles this node type via type cast — it creates a
    // CheckedContinuation and emits it via PipelineEvent.pausedForReview so
    // the caller owns the resume decision. This passthrough satisfies the protocol.
    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        return context
    }
}
