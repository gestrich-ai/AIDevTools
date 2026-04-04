public enum PipelineEvent: Sendable {
    case nodeCompleted(id: String, displayName: String)
    case nodeProgress(id: String, progress: PipelineNodeProgress)
    case nodeStarted(id: String, displayName: String)
    case pausedForReview(continuation: CheckedContinuation<Void, any Error>)
    case taskDiscovered(id: String, displayName: String)
    case completed(context: PipelineContext)
}
