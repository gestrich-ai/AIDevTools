import Foundation

public enum MCPStatus: Sendable {
    case binaryMissing
    case notConfigured
    case ready(binaryURL: URL, builtAt: Date)

    public var daysStale: Int? {
        guard case .ready(_, let builtAt) = self else { return nil }
        return Calendar.current.dateComponents([.day], from: builtAt, to: .now).day
    }
}
