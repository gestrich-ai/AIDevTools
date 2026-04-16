import Foundation

/// Represents a single hunk from a git diff
@preconcurrency public struct Hunk: Identifiable, Equatable, Codable, Sendable {
    /// The path of the modified file (from b/ path in diff)
    public let filePath: String
    /// The full content of the hunk including header
    public let content: String
    /// The raw header lines from the diff
    public let rawHeader: [String]
    /// Starting line number in the old file
    public let oldStart: Int
    /// Number of lines in the old file section
    public let oldLength: Int
    /// Starting line number in the new file
    public let newStart: Int
    /// Number of lines in the new file section
    public let newLength: Int

    public init(
        filePath: String,
        content: String,
        rawHeader: [String] = [],
        oldStart: Int = 0,
        oldLength: Int = 0,
        newStart: Int = 0,
        newLength: Int = 0
    ) {
        self.filePath = filePath
        self.content = content
        self.rawHeader = rawHeader
        self.oldStart = oldStart
        self.oldLength = oldLength
        self.newStart = newStart
        self.newLength = newLength
    }

    /// Unique identifier for this hunk (used for Identifiable)
    public var id: String {
        chunkName
    }

    /// Generate a unique name for this hunk
    public var chunkName: String {
        let safeName = filePath.replacingOccurrences(of: "/", with: "_")
        return "\(safeName)_L\(newStart)"
    }

    /// Extract the filename from the file path
    public var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    /// Extract the file extension from the file path
    public var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension
    }

    /// Get just the diff lines (without headers or @@ lines)
    public var diffLines: [String] {
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var inDiffContent = false

        for line in lines {
            // Skip headers at the beginning
            if !inDiffContent {
                if line.hasPrefix("diff --git") ||
                   line.hasPrefix("index ") ||
                   line.hasPrefix("--- ") ||
                   line.hasPrefix("+++ ") {
                    continue
                } else if line.hasPrefix("@@") {
                    inDiffContent = true
                    continue
                }
            }

            // Add actual diff lines
            if inDiffContent && !line.isEmpty {
                result.append(line)
            }
        }

        return result
    }

    /// Create a Hunk from raw diff data
    public static func fromHunkData(fileHeader: [String], hunkLines: [String], filePath: String?) -> Hunk? {
        guard let filePath else { return nil }

        // Extract line numbers from @@ line
        var oldStart = 0
        var oldLength = 0
        var newStart = 0
        var newLength = 0

        for line in hunkLines {
            if line.hasPrefix("@@") {
                // Parse the @@ -14,11 +14,11 @@ format
                let pattern = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)

                if let match = regex?.firstMatch(in: line, options: [], range: nsRange) {
                    if let oldStartRange = Range(match.range(at: 1), in: line) {
                        oldStart = Int(line[oldStartRange]) ?? 0
                    }
                    if let oldLengthRange = Range(match.range(at: 2), in: line) {
                        oldLength = Int(line[oldLengthRange]) ?? 1
                    } else {
                        oldLength = 1 // Default to 1 if not specified
                    }
                    if let newStartRange = Range(match.range(at: 3), in: line) {
                        newStart = Int(line[newStartRange]) ?? 0
                    }
                    if let newLengthRange = Range(match.range(at: 4), in: line) {
                        newLength = Int(line[newLengthRange]) ?? 1
                    } else {
                        newLength = 1 // Default to 1 if not specified
                    }
                }
                break
            }
        }

        let content = (fileHeader + hunkLines).joined(separator: "\n")

        return Hunk(
            filePath: filePath,
            content: content,
            rawHeader: fileHeader,
            oldStart: oldStart,
            oldLength: oldLength,
            newStart: newStart,
            newLength: newLength
        )
    }
}
