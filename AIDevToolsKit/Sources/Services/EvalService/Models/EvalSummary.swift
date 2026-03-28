import Foundation

public struct EvalSummary: Codable, Sendable {
    public let provider: String
    public let total: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let cases: [CaseResult]

    public init(
        provider: String,
        total: Int,
        passed: Int,
        failed: Int,
        skipped: Int,
        cases: [CaseResult]
    ) {
        self.provider = provider
        self.total = total
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.cases = cases
    }
}
