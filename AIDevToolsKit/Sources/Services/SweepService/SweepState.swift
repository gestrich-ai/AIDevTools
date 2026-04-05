import Foundation

/// Persisted progress for a sweep.
public struct SweepState: Codable, Sendable {
    /// The last file path processed, used to resume on the next run.
    public var cursor: String?
    /// When the sweep last ran successfully.
    public var lastRunDate: Date?

    public init(cursor: String? = nil, lastRunDate: Date? = nil) {
        self.cursor = cursor
        self.lastRunDate = lastRunDate
    }

    /// Loads state from `url`, returning an empty state if the file does not exist.
    public static func load(from url: URL) throws -> SweepState {
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return SweepState()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SweepState.self, from: data)
    }

    /// Persists the state to `url`, creating intermediate directories as needed.
    public func save(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
