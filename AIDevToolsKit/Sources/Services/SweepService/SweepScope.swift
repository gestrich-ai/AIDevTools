import Foundation

/// A path range that bounds a sweep run.
public struct SweepScope: Codable, Sendable {
    /// The file path at which the sweep begins.
    public let from: String
    /// The file path at which the sweep stops, or `nil` to run through the end.
    public let to: String?

    public init(from: String, to: String? = nil) {
        self.from = from
        self.to = to
    }
}
