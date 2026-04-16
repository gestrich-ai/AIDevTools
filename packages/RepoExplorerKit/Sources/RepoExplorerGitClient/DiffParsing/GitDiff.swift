import Foundation

/// Represents a complete git diff with all its hunks
@preconcurrency public struct GitDiff: Equatable, Codable, Sendable {
    /// The raw diff content
    public let rawContent: String
    /// List of parsed hunks
    public let hunks: [Hunk]
    /// The git commit hash for this diff (optional)
    public let commitHash: String?

    public init(rawContent: String, hunks: [Hunk], commitHash: String? = nil) {
        self.rawContent = rawContent
        self.hunks = hunks
        self.commitHash = commitHash
    }

    /// Parse diff content into a GitDiff structure
    public static func fromDiffContent(_ diffContent: String, commitHash: String? = nil) -> GitDiff {
        let lines = diffContent.components(separatedBy: .newlines)
        var currentHunk: [String] = []
        var fileHeader: [String] = []
        var currentFile: String?
        var inHunk = false
        var hunks: [Hunk] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("diff --git") {
                // Save previous hunk if exists
                if !currentHunk.isEmpty, let file = currentFile {
                    if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file) {
                        hunks.append(hunk)
                    }
                    currentHunk = []
                    fileHeader = []
                }

                // Extract the current file name using regex to handle spaces in paths
                currentFile = extractFilePath(from: line)
                fileHeader = [line]
                inHunk = false
            } else if line.hasPrefix("index ") {
                fileHeader.append(line)
            } else if line.hasPrefix("--- ") {
                fileHeader.append(line)
            } else if line.hasPrefix("+++ ") {
                fileHeader.append(line)
            } else if line.hasPrefix("@@") {
                // Start of a new hunk
                if !currentHunk.isEmpty, let file = currentFile {
                    if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file) {
                        hunks.append(hunk)
                    }
                    currentHunk = []
                }
                inHunk = true
                currentHunk.append(line)
            } else if inHunk {
                // The code lines of the hunk
                currentHunk.append(line)
            }

            i += 1
        }

        // Don't forget the last hunk
        if !currentHunk.isEmpty, let file = currentFile {
            if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file) {
                hunks.append(hunk)
            }
        }

        return GitDiff(rawContent: diffContent, hunks: hunks, commitHash: commitHash)
    }

    /// Check if the diff is empty
    public var isEmpty: Bool {
        rawContent.isEmpty || hunks.isEmpty
    }

    /// Get hunks filtered by file extensions
    public func getHunks(byFileExtensions extensions: [String]?) -> [Hunk] {
        guard let extensions else { return hunks }
        return hunks.filter { extensions.contains($0.fileExtension) }
    }

    /// Get all hunks for a specific file path
    public func getHunks(byFilePath filePath: String) -> [Hunk] {
        hunks.filter { $0.filePath == filePath }
    }

    /// Find the hunk that contains a specific line number in the new file
    /// - Parameters:
    ///   - lineNumber: The line number in the new/current version of the file (1-based)
    ///   - filePath: The file path to search in
    /// - Returns: The hunk containing the line, or nil if not found
    public func findHunk(containingLine lineNumber: Int, inFile filePath: String) -> Hunk? {
        let fileHunks = getHunks(byFilePath: filePath)

        for hunk in fileHunks {
            // Check if the line falls within this hunk's range in the new file
            // newStart is 1-based, and we need to check if lineNumber is within the range
            let hunkEndLine = hunk.newStart + hunk.newLength - 1
            if lineNumber >= hunk.newStart && lineNumber <= hunkEndLine {
                return hunk
            }
        }

        return nil
    }

    /// Get list of all changed files
    public var changedFiles: [String] {
        Array(Set(hunks.map(\.filePath))).sorted()
    }

    /// Get diff lines grouped by file for display
    public func diffSections() -> [DiffSection] {
        var sections: [String: [DiffLine]] = [:]

        for hunk in hunks {
            if sections[hunk.filePath] == nil {
                sections[hunk.filePath] = []
            }

            // Use the structured diffLines property from Hunk
            for line in hunk.diffLines {
                let type: DiffLineType
                if line.hasPrefix("+") {
                    type = .addition
                } else if line.hasPrefix("-") {
                    type = .deletion
                } else {
                    type = .context
                }
                sections[hunk.filePath]?.append(DiffLine(content: line, type: type))
            }
        }

        return sections.map { DiffSection(filePath: $0.key, lines: $0.value) }
            .sorted { $0.filePath < $1.filePath }
    }

    /// Extract changed line numbers from the diff
    public func getChangedLines() -> [String: Set<Int>] {
        var changedLines: [String: Set<Int>] = [:]

        for hunk in hunks {
            if changedLines[hunk.filePath] == nil {
                changedLines[hunk.filePath] = Set<Int>()
            }

            // Parse hunk content to find actually changed lines
            let lines = hunk.content.components(separatedBy: .newlines)
            var currentNewLine = hunk.newStart
            var inDiffContent = false

            for line in lines {
                if line.hasPrefix("@@") {
                    inDiffContent = true
                    continue
                } else if !inDiffContent {
                    continue
                } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    // This is an added line
                    changedLines[hunk.filePath]?.insert(currentNewLine)
                    currentNewLine += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    // This is a removed line - don't increment new line counter
                    continue
                } else if line.hasPrefix(" ") {
                    // This is a context line (unchanged)
                    currentNewLine += 1
                } else if inDiffContent && !line.isEmpty {
                    // Treat as context line if we're in diff content
                    currentNewLine += 1
                }
            }
        }

        return changedLines
    }

    // Helper function to extract file path from diff --git line
    private static func extractFilePath(from line: String) -> String? {
        // Try to match quoted paths first (for paths with spaces)
        let quotedPattern = #"diff --git "?a/([^"]*)"? "?b/([^"]*)"?"#
        if let regex = try? NSRegularExpression(pattern: quotedPattern, options: []) {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: nsRange),
               let range = Range(match.range(at: 2), in: line) {
                return String(line[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Fallback to simple pattern
        let simplePattern = #"diff --git a/(.*?) b/(.*?)(?:\s|$)"#
        if let regex = try? NSRegularExpression(pattern: simplePattern, options: []) {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: nsRange),
               let range = Range(match.range(at: 2), in: line) {
                return String(line[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }
}

/// Represents a section of diff lines for a single file
public struct DiffSection: Identifiable, Equatable {
    public let id = UUID()
    public let filePath: String
    public let lines: [DiffLine]
    public let isStaged: Bool

    public init(filePath: String, lines: [DiffLine], isStaged: Bool = false) {
        self.filePath = filePath
        self.lines = lines
        self.isStaged = isStaged
    }
}

/// Represents a single line in a diff for display purposes
public struct DiffLine: Identifiable, Equatable {
    public let id = UUID()
    public let content: String
    public let type: DiffLineType

    public init(content: String, type: DiffLineType) {
        self.content = content
        self.type = type
    }
}

public enum DiffLineType: Equatable {
    case addition
    case deletion
    case context
}
