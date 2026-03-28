public struct EvalRunOutput: Sendable {
    public let rawStdout: String
    public let result: ProviderResult
    public let stderr: String

    public init(result: ProviderResult, rawStdout: String, stderr: String) {
        self.rawStdout = rawStdout
        self.result = result
        self.stderr = stderr
    }
}
