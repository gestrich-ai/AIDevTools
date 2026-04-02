public enum PipelineEvent: Sendable {
    case nodeStarted(id: String, displayName: String)
    case nodeCompleted(id: String, displayName: String)
    case nodeProgress(id: String, progress: PipelineNodeProgress)
    case pausedForReview
    case completed(context: PipelineContext)
}
