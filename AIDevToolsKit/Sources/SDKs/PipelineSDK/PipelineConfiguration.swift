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
