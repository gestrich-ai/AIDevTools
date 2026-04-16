import Foundation

/// A hunk enriched with blame information for each line
public struct EnrichedHunk: Equatable, Codable {
    /// The original diff hunk
    public let hunk: Hunk
    /// Blame information for lines in this hunk (keyed by line number)
    public let blameInfo: [Int: BlameInfo]

    public init(hunk: Hunk, blameInfo: [Int: BlameInfo] = [:]) {
        self.hunk = hunk
        self.blameInfo = blameInfo
    }
}

/// A diff enriched with blame information
public struct EnrichedDiff: Equatable, Codable {
    /// The raw diff content
    public let rawContent: String
    /// List of enriched hunks with blame info
    public let enrichedHunks: [EnrichedHunk]
    /// The git commit hash for this diff (optional)
    public let commitHash: String?
    /// Full file content if available
    public let fileContent: String?

    public init(
        rawContent: String,
        enrichedHunks: [EnrichedHunk],
        commitHash: String? = nil,
        fileContent: String? = nil
    ) {
        self.rawContent = rawContent
        self.enrichedHunks = enrichedHunks
        self.commitHash = commitHash
        self.fileContent = fileContent
    }

    /// Create from a regular GitDiff without blame info
    public static func fromGitDiff(_ diff: GitDiff, fileContent: String? = nil) -> EnrichedDiff {
        let enrichedHunks = diff.hunks.map { hunk in
            EnrichedHunk(hunk: hunk, blameInfo: [:])
        }
        return EnrichedDiff(
            rawContent: diff.rawContent,
            enrichedHunks: enrichedHunks,
            commitHash: diff.commitHash,
            fileContent: fileContent
        )
    }

    /// Check if the diff is empty
    public var isEmpty: Bool {
        rawContent.isEmpty || enrichedHunks.isEmpty
    }

    /// Get all changed files
    public var changedFiles: [String] {
        Array(Set(enrichedHunks.map(\.hunk.filePath))).sorted()
    }

    /// Get enriched hunks for a specific file
    public func getHunks(byFilePath filePath: String) -> [EnrichedHunk] {
        enrichedHunks.filter { $0.hunk.filePath == filePath }
    }

    /// Extract changed lines with their blame info
    public func getChangedLinesWithBlame() -> [String: [Int: BlameInfo]] {
        var result: [String: [Int: BlameInfo]] = [:]

        for enrichedHunk in enrichedHunks {
            let filePath = enrichedHunk.hunk.filePath
            if result[filePath] == nil {
                result[filePath] = [:]
            }

            // Merge blame info for this hunk
            for (lineNum, blame) in enrichedHunk.blameInfo {
                result[filePath]?[lineNum] = blame
            }
        }

        return result
    }

    /// Get line change type (added, removed, unchanged) for display
    public func getLineChangeTypes(for filePath: String) -> [Int: LineChangeType] {
        var changeTypes: [Int: LineChangeType] = [:]

        for enrichedHunk in getHunks(byFilePath: filePath) {
            let lines = enrichedHunk.hunk.content.components(separatedBy: .newlines)
            var currentNewLine = enrichedHunk.hunk.newStart
            var inDiffContent = false

            for line in lines {
                if line.hasPrefix("@@") {
                    inDiffContent = true
                    continue
                } else if !inDiffContent {
                    continue
                } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    changeTypes[currentNewLine] = .added
                    currentNewLine += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    // Removed lines don't have a new line number
                    continue
                } else if line.hasPrefix(" ") {
                    changeTypes[currentNewLine] = .unchanged
                    currentNewLine += 1
                } else if inDiffContent && !line.isEmpty {
                    changeTypes[currentNewLine] = .unchanged
                    currentNewLine += 1
                }
            }
        }

        return changeTypes
    }
}

/// Type of change for a line in a diff
public enum LineChangeType: String, Codable {
    case added = "+"
    case removed = "-"
    case unchanged = " "
}

/// Represents a file with both diff and blame information
public struct EnrichedFileData: Codable {
    public let filePath: String
    public let fileContent: String
    public let enrichedDiff: EnrichedDiff?
    public let blameSections: [BlameSection]

    public init(
        filePath: String,
        fileContent: String,
        enrichedDiff: EnrichedDiff? = nil,
        blameSections: [BlameSection] = []
    ) {
        self.filePath = filePath
        self.fileContent = fileContent
        self.enrichedDiff = enrichedDiff
        self.blameSections = blameSections
    }

    /// Get the lines of the file
    public var lines: [String] {
        fileContent.components(separatedBy: .newlines)
    }

    /// Get blame section for a specific line
    public func blameSection(for lineNumber: Int) -> BlameSection? {
        blameSections.first { section in
            lineNumber >= section.startLine && lineNumber <= section.endLine
        }
    }

    /// Check if a line was changed in the diff
    public func isLineChanged(_ lineNumber: Int) -> Bool {
        guard let diff = enrichedDiff else { return false }
        let changeTypes = diff.getLineChangeTypes(for: filePath)
        return changeTypes[lineNumber] == .added
    }

    /// Get the type of change for a line
    public func lineChangeType(_ lineNumber: Int) -> LineChangeType? {
        guard let diff = enrichedDiff else { return nil }
        let changeTypes = diff.getLineChangeTypes(for: filePath)
        return changeTypes[lineNumber]
    }
}
