import AIOutputSDK

public protocol PipelineNode: Sendable {
    var id: String { get }
    var displayName: String { get }

    func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext
}

public enum PipelineNodeProgress: Sendable {
    case contentBlocks([AIContentBlock])
    case custom(String)
    case output(String)
    case pausedForReview
    case userPrompt(String)
}
