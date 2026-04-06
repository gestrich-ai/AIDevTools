import Foundation

public enum WorktreeError: LocalizedError {
    case addFailed(String)
    case listFailed(String)
    case removeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .addFailed(let detail): "Failed to add worktree: \(detail)"
        case .listFailed(let detail): "Failed to list worktrees: \(detail)"
        case .removeFailed(let detail): "Failed to remove worktree: \(detail)"
        }
    }
}
