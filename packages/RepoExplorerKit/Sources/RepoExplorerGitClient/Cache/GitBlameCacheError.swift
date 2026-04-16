import Foundation

/// Errors that can occur during Git blame cache operations
public enum GitBlameCacheError: Error, LocalizedError {
    case containerInitializationFailed(Error)
    case modelContextCreationFailed
    case fetchFailed(Error)
    case saveFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .containerInitializationFailed(let error):
            return "Failed to initialize SwiftData container: \(error.localizedDescription)"
        case .modelContextCreationFailed:
            return "Failed to create SwiftData model context"
        case .fetchFailed(let error):
            return "Failed to fetch from cache: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save to cache: \(error.localizedDescription)"
        }
    }
}
