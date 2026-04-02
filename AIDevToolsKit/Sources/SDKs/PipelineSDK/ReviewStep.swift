public struct ReviewStepData: PipelineStep {
    public let id: String
    public let description: String
    public let isCompleted: Bool
    public let scope: ReviewScope
    public let prompt: String
    public let reviewedStepIDs: [String]

    public init(
        id: String,
        description: String,
        isCompleted: Bool,
        scope: ReviewScope,
        prompt: String,
        reviewedStepIDs: [String]
    ) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
        self.scope = scope
        self.prompt = prompt
        self.reviewedStepIDs = reviewedStepIDs
    }
}