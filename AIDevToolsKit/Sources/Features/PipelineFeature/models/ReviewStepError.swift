import Foundation

public enum ReviewStepError: Error, LocalizedError {
    case gitDiffFailed(arguments: String, output: String)
    
    public var errorDescription: String? {
        switch self {
        case .gitDiffFailed(let arguments, let output):
            return "Git diff failed with arguments: \(arguments)\nOutput: \(output)"
        }
    }
}