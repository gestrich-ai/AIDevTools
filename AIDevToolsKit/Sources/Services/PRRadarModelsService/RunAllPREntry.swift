import Foundation

public struct RunAllPREntry: Sendable {
    public let entry: PRManifestEntry
    public let summary: ReportSummary?

    public init(entry: PRManifestEntry, summary: ReportSummary?) {
        self.entry = entry
        self.summary = summary
    }
}
