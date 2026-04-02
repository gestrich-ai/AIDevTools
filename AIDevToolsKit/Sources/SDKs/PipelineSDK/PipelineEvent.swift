public enum PipelineEvent: Sendable {
    case nodeStarted(id: String, displayName: String)
    case nodeCompleted(id: String, displayName: String)
    case nodeProgress(id: String, progress: PipelineNodeProgress)
    case pausedForReview(continuation: CheckedContinuation<Void, any Error>)
    case completed(context: PipelineContext)
}
