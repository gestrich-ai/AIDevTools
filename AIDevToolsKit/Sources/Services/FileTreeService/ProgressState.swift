import Foundation

public enum ProgressState: Sendable {
    case idle
    case indexingDirectories
    case indexingFiles(current: Int, total: Int)
    case indexingGitignore
    case loadingCache
    case revalidating

    public var isActive: Bool {
        switch self {
        case .idle:
            false
        default:
            true
        }
    }

    public var message: String {
        switch self {
        case .idle:
            ""
        case .indexingDirectories:
            "Indexing... (Scanning directories)"
        case .indexingFiles(let current, let total):
            "Indexing... (Scanning files: \(current)/\(total))"
        case .indexingGitignore:
            "Indexing... (Scanning .gitignore files)"
        case .loadingCache:
            "Loading... (Reading cache from disk)"
        case .revalidating:
            "Revalidating..."
        }
    }
}
