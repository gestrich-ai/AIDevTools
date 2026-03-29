import Foundation

public enum CreatePRError: Error, LocalizedError {
    case commandFailed(command: String, output: String)
    
    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let output):
            return "Command failed: \(command)\nOutput: \(output)"
        }
    }
}