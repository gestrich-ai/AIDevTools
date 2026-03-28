import Foundation

public struct ProviderResult: Sendable {
    public let provider: Provider
    public var error: ProviderError?
    public var events: [[String: JSONValue]]
    public var metrics: ProviderMetrics?
    public var rawStderrPath: URL?
    public var rawStdoutPath: URL?
    public var rawTracePath: URL?
    public var resultText: String?
    public var structuredOutput: [String: JSONValue]?
    public var toolCallSummary: ToolCallSummary?
    public var toolEvents: [ToolEvent]

    public init(
        provider: Provider,
        structuredOutput: [String: JSONValue]? = nil,
        resultText: String? = nil,
        events: [[String: JSONValue]] = [],
        toolEvents: [ToolEvent] = [],
        metrics: ProviderMetrics? = nil,
        rawStdoutPath: URL? = nil,
        rawStderrPath: URL? = nil,
        rawTracePath: URL? = nil,
        error: ProviderError? = nil,
        toolCallSummary: ToolCallSummary? = nil
    ) {
        self.provider = provider
        self.error = error
        self.events = events
        self.metrics = metrics
        self.rawStderrPath = rawStderrPath
        self.rawStdoutPath = rawStdoutPath
        self.rawTracePath = rawTracePath
        self.resultText = resultText
        self.structuredOutput = structuredOutput
        self.toolCallSummary = toolCallSummary
        self.toolEvents = toolEvents
    }
}
