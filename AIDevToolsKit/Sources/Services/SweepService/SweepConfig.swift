import Foundation

/// Configuration for a single sweep run.
public struct SweepConfig: Sendable {
    /// Maximum number of files to scan.
    public let scanLimit: Int
    /// Maximum number of files to change.
    public let changeLimit: Int
    /// Glob pattern selecting files eligible for the sweep.
    public let filePattern: String
    /// Optional path range restricting which files are considered.
    public let scope: SweepScope?

    /// `true` when `filePattern` ends with `/`, indicating directory-based iteration.
    public var isDirectoryMode: Bool { filePattern.hasSuffix("/") }

    public init(scanLimit: Int = 1, changeLimit: Int = 1, filePattern: String, scope: SweepScope? = nil) {
        self.scanLimit = scanLimit
        self.changeLimit = changeLimit
        self.filePattern = filePattern
        self.scope = scope
    }
}
