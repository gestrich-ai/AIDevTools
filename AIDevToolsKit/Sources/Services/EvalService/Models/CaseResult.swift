import AIOutputSDK
import Foundation

public struct CaseResult: Codable, Sendable {
    public let caseId: String
    public let passed: Bool
    public let errors: [String]
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

    public func appendingErrors(_ additionalErrors: [String]) -> CaseResult {
        guard !additionalErrors.isEmpty else {
            return self
        }

        return CaseResult(
            caseId: caseId,
            passed: passed,
            errors: errors + additionalErrors,
            skipped: skipped,
            skillChecks: skillChecks,
            task: task,
            input: input,
            expected: expected,
            mustInclude: mustInclude,
            mustNotInclude: mustNotInclude,
            providerResponse: providerResponse,
            toolCallSummary: toolCallSummary
        )
    }

    public func withPassed(_ passed: Bool) -> CaseResult {
        CaseResult(
            caseId: caseId,
            passed: passed,
            errors: errors,
            skipped: skipped,
            skillChecks: skillChecks,
            task: task,
            input: input,
            expected: expected,
            mustInclude: mustInclude,
            mustNotInclude: mustNotInclude,
            providerResponse: providerResponse,
            toolCallSummary: toolCallSummary
        )
    }
}
