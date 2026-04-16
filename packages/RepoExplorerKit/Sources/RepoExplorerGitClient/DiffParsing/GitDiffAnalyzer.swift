import RepoExplorerCLITools
import Foundation

/// Analyzes git diffs from local repositories or raw diff text
public class GitDiffAnalyzer {
    private let repoPath: String?
    private let cliService = CLIService.shared
    private let gitBuilder = CommandBuilder().git()

    /// Initialize with a local repository path
    public init(repoPath: String? = nil) {
        self.repoPath = repoPath
    }

    // MARK: - Local Repository Methods

    /// Get diff between two commits/branches in a local repository
    public func getDiff(base: String, target: String? = nil) async throws -> GitDiff {
        guard let repoPath else {
            throw GitError.invalidPath("Repository path not set")
        }

        let targetRef = target ?? "HEAD"
        let arguments = ["diff", "\(base)...\(targetRef)"]

        let result = try await cliService.execute(
            command: "/usr/bin/git",
            arguments: arguments,
            workingDirectory: repoPath
        )

        guard result.isSuccess else {
            throw GitError.commandFailed("Failed to get diff: \(result.stderr)")
        }

        return GitDiff.fromDiffContent(result.stdout, commitHash: targetRef)
    }

    /// Get diff for a specific commit
    public func getCommitDiff(_ commitHash: String) async throws -> GitDiff {
        guard let repoPath else {
            throw GitError.invalidPath("Repository path not set")
        }

        let arguments = ["show", commitHash]

        let result = try await cliService.execute(
            command: "/usr/bin/git",
            arguments: arguments,
            workingDirectory: repoPath
        )

        guard result.isSuccess else {
            throw GitError.commandFailed("Failed to get commit diff: \(result.stderr)")
        }

        return GitDiff.fromDiffContent(result.stdout, commitHash: commitHash)
    }

    /// Get diff for staged changes
    public func getStagedDiff() async throws -> GitDiff {
        guard let repoPath else {
            throw GitError.invalidPath("Repository path not set")
        }

        let arguments = ["diff", "--cached"]

        let result = try await cliService.execute(
            command: "/usr/bin/git",
            arguments: arguments,
            workingDirectory: repoPath
        )

        guard result.isSuccess else {
            throw GitError.commandFailed("Failed to get staged diff: \(result.stderr)")
        }

        return GitDiff.fromDiffContent(result.stdout)
    }

    /// Get diff for unstaged changes
    public func getUnstagedDiff() async throws -> GitDiff {
        guard let repoPath else {
            throw GitError.invalidPath("Repository path not set")
        }

        let arguments = ["diff"]

        let result = try await cliService.execute(
            command: "/usr/bin/git",
            arguments: arguments,
            workingDirectory: repoPath
        )

        guard result.isSuccess else {
            throw GitError.commandFailed("Failed to get unstaged diff: \(result.stderr)")
        }

        return GitDiff.fromDiffContent(result.stdout)
    }

    // MARK: - Text Parsing Methods

    /// Parse raw diff text directly
    public func parseDiffText(_ diffText: String, commitHash: String? = nil) -> GitDiff {
        return GitDiff.fromDiffContent(diffText, commitHash: commitHash)
    }

    /// Parse diff from a file
    public func parseDiffFile(at path: String, commitHash: String? = nil) throws -> GitDiff {
        let diffContent = try String(contentsOfFile: path)
        return GitDiff.fromDiffContent(diffContent, commitHash: commitHash)
    }

    // MARK: - Analysis Methods

    /// Filter a list of items to only those that appear in changed lines
    public func filterByChangedLines<T>(
        items: [T],
        diff: GitDiff,
        filePathExtractor: (T) -> String,
        lineExtractor: (T) -> Int
    ) -> [T] {
        let changedLines = diff.getChangedLines()

        return items.filter { item in
            let filePath = filePathExtractor(item)
            let line = lineExtractor(item)

            // Check if this file has changes and if the line is in the changed set
            if let fileChanges = changedLines[filePath] {
                return fileChanges.contains(line)
            }
            return false
        }
    }

    /// Get statistics about the diff
    public func getDiffStatistics(_ diff: GitDiff) -> DiffStatistics {
        var addedLines = 0
        var removedLines = 0
        var modifiedFiles = Set<String>()

        for hunk in diff.hunks {
            modifiedFiles.insert(hunk.filePath)

            let lines = hunk.content.components(separatedBy: .newlines)
            for line in lines {
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    addedLines += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    removedLines += 1
                }
            }
        }

        return DiffStatistics(
            filesChanged: modifiedFiles.count,
            linesAdded: addedLines,
            linesRemoved: removedLines,
            totalHunks: diff.hunks.count
        )
    }

    /// Check if a specific file and line was changed in the diff
    public func isLineChanged(filePath: String, line: Int, in diff: GitDiff) -> Bool {
        let changedLines = diff.getChangedLines()
        return changedLines[filePath]?.contains(line) ?? false
    }

    /// Get all changed files of specific types
    public func getChangedFiles(withExtensions extensions: [String], in diff: GitDiff) -> [String] {
        let extensionSet = Set(extensions)
        return diff.changedFiles.filter { path in
            let fileExtension = URL(fileURLWithPath: path).pathExtension
            return extensionSet.contains(fileExtension)
        }
    }
}

/// Statistics about a git diff
public struct DiffStatistics {
    public let filesChanged: Int
    public let linesAdded: Int
    public let linesRemoved: Int
    public let totalHunks: Int
}

// Extension to support GitError if not already defined
extension GitError {
    static func invalidPath(_ message: String) -> GitError {
        return GitError(message: message)
    }

    static func commandFailed(_ message: String) -> GitError {
        return GitError(message: message)
    }
}

// Basic GitError if not already defined elsewhere
public struct GitError: Error, LocalizedError {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        return message
    }
}
