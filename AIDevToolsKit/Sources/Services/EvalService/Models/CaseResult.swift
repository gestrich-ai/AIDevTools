import AIOutputSDK
import Foundation

public struct CaseResult: Codable, Sendable {
    public let caseId: String
    public var passed: Bool
    public var errors: [String]
    public let skipped: [String]
    public let skillChecks: [SkillCheckResult]
    public let task: String?
    public let input: String?
    public let expected: String?
    public let mustInclude: [String]?
    public let mustNotInclude: [String]?
    public let providerResponse: String?
    public let toolCallSummary: ToolCallSummary?

    public init(
        caseId: String,
        passed: Bool,
        errors: [String] = [],
        skipped: [String] = [],
        skillChecks: [SkillCheckResult] = [],
        task: String? = nil,
        input: String? = nil,
        expected: String? = nil,
        mustInclude: [String]? = nil,
        mustNotInclude: [String]? = nil,
        providerResponse: String? = nil,
        toolCallSummary: ToolCallSummary? = nil
    ) {
        self.caseId = caseId
        self.passed = passed
        self.errors = errors
        self.skipped = skipped
        self.skillChecks = skillChecks
        self.task = task
        self.input = input
        self.expected = expected
        self.mustInclude = mustInclude
        self.mustNotInclude = mustNotInclude
        self.providerResponse = providerResponse
        self.toolCallSummary = toolCallSummary
    }
}
