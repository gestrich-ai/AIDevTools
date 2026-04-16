import Foundation

/// Result of a command execution
public struct CommandResult: Sendable {
    public let output: String
    public let error: String
    public let exitCode: Int32
    
    public var success: Bool {
        return exitCode == 0
    }
    
    public var trimmedOutput: String {
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var trimmedError: String {
        return error.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public init(output: String, error: String, exitCode: Int32) {
        self.output = output
        self.error = error
        self.exitCode = exitCode
    }
}
