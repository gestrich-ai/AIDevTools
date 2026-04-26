import Foundation

public struct CacheRefreshState: Codable, Sendable {
    public let lastCheckedAt: Date

    public init(lastCheckedAt: Date = Date()) {
        self.lastCheckedAt = lastCheckedAt
    }

    public static var fallbackDate: Date {
        Date().addingTimeInterval(-60 * 24 * 60 * 60)
    }
}
