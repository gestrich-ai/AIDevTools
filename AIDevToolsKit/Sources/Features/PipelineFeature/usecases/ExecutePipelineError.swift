import Foundation

public enum ExecutePipelineError: Error, LocalizedError {
    case noHandlerFound(stepDescription: String)

    public var errorDescription: String? {
        switch self {
        case .noHandlerFound(let desc):
            return "No handler registered for step: \(desc)"
        }
    }
}