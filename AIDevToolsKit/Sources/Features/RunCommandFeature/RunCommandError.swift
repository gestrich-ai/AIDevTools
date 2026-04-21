import Foundation

public enum RunCommandError: LocalizedError, Sendable {
    case commandNotFound(UUID)
    case executionFailed(exitCode: Int32, output: String)
    case repositoryNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound(let id):
            return "Run command not found: \(id)"
        case .executionFailed(let code, let output):
            let suffix = output.isEmpty ? "" : ": \(output)"
            return "Command failed (exit \(code))\(suffix)"
        case .repositoryNotFound(let id):
            return "Repository not found: \(id)"
        }
    }
}
