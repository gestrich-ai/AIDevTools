import Foundation

public enum GitRepoError: Error {
    case gitCommandFailed(String)
    case invalidBlameOutput
    case repositoryNotFound
    case commitNotFound(String)
    case pathNotFound(String)
}

extension GitRepoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .gitCommandFailed(let message):
            return "Git command failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .invalidBlameOutput:
            return "Invalid git blame output format"
        case .repositoryNotFound:
            return "Git repository not found"
        case .commitNotFound(let sha):
            return "Commit not found: \(sha)"
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        }
    }
}
