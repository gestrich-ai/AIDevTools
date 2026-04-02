import AIOutputSDK

public struct PipelineConfiguration: Sendable {
    public let executionMode: ExecutionMode
    public let maxMinutes: Int?
    public let provider: any AIClient
    public let stagingOnly: Bool

    public init(
        executionMode: ExecutionMode = .all,
        maxMinutes: Int? = nil,
        provider: any AIClient,
        stagingOnly: Bool = false
    ) {
        self.executionMode = executionMode
        self.maxMinutes = maxMinutes
        self.provider = provider
        self.stagingOnly = stagingOnly
    }

    public enum ExecutionMode: Sendable {
        case all
        case nextOnly
    }
}

public struct PRConfiguration: Sendable {
    public let assignees: [String]
    public let labels: [String]
    public let maxOpenPRs: Int?
    public let reviewers: [String]

    public init(
        assignees: [String] = [],
        labels: [String] = [],
        maxOpenPRs: Int? = nil,
        reviewers: [String] = []
    ) {
        self.assignees = assignees
        self.labels = labels
        self.maxOpenPRs = maxOpenPRs
        self.reviewers = reviewers
    }
}
