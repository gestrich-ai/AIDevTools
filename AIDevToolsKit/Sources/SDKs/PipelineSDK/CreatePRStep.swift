public struct PRStepData: PipelineStep {
    public let id: String
    public let description: String
    public let isCompleted: Bool
    public let titleTemplate: String
    public let bodyTemplate: String
    public let label: String?

    public init(
        id: String,
        description: String,
        isCompleted: Bool,
        titleTemplate: String,
        bodyTemplate: String,
        label: String?
    ) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
        self.titleTemplate = titleTemplate
        self.bodyTemplate = bodyTemplate
        self.label = label
    }
}