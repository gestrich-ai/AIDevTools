import Foundation

public enum CodeChangeError: Error, LocalizedError {
    case executionFailed(stepId: String, stderr: String)
    
    public var errorDescription: String? {
        switch self {
        case .executionFailed(let stepId, let stderr):
            return "Code change step \(stepId) failed: \(stderr)"
        }
    }
}