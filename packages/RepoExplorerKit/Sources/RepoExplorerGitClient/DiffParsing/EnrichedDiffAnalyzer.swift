import RepoExplorerCLITools
import Foundation

/// Analyzes git diffs and enriches them with blame information
public class EnrichedDiffAnalyzer {
    private let repoPath: String
    private let gitRepo: GitRepo
    private let diffAnalyzer: GitDiffAnalyzer
    private let cliService = CLIService.shared
    private let gitBuilder = CommandBuilder().git()

    /// Initialize with a repository path
    public init(repoPath: String) {
        self.repoPath = repoPath
        self.gitRepo = GitRepo(repoPath: repoPath)
        self.diffAnalyzer = GitDiffAnalyzer(repoPath: repoPath)
    }

    // MARK: - Enriched Diff Methods

    /// Get an enriched diff between two commits/branches with blame info
    public func getEnrichedDiff(
        base: String,
        target: String? = nil,
        includeBlame: Bool = true
    ) async throws -> EnrichedDiff {
        // Get the basic diff first
        let gitDiff = try await diffAnalyzer.getDiff(base: base, target: target)

        if !includeBlame {
            return EnrichedDiff.fromGitDiff(gitDiff)
        }

        // Enrich hunks with blame information
        var enrichedHunks: [EnrichedHunk] = []

        for hunk in gitDiff.hunks {
            let blameInfo = try await getBlameForHunk(hunk)
            let enrichedHunk = EnrichedHunk(hunk: hunk, blameInfo: blameInfo)
            enrichedHunks.append(enrichedHunk)
        }

        return EnrichedDiff(
            rawContent: gitDiff.rawContent,
            enrichedHunks: enrichedHunks,
            commitHash: gitDiff.commitHash
        )
    }

    /// Get enriched file data with both diff and full blame information
    public func getEnrichedFileData(
        filePath: String,
        base: String? = nil,
        target: String? = nil
    ) async throws -> EnrichedFileData {
        // Get the file content
        let fileContent = try await gitRepo.getFileContent(path: filePath) ?? ""

        // Get full blame data for the file
        let blameData = try await gitRepo.getFullBlameData(for: filePath)

        // Get diff if base is provided
        var enrichedDiff: EnrichedDiff?
        if let base {
            let gitDiff = try await diffAnalyzer.getDiff(base: base, target: target)

            // Filter to just this file's hunks
            let fileHunks = gitDiff.hunks.filter { $0.filePath == filePath }

            if !fileHunks.isEmpty {
                // Enrich the hunks with blame info
                var enrichedHunks: [EnrichedHunk] = []
                for hunk in fileHunks {
                    let blameInfo = try await getBlameForHunk(hunk)
                    enrichedHunks.append(EnrichedHunk(hunk: hunk, blameInfo: blameInfo))
                }

                enrichedDiff = EnrichedDiff(
                    rawContent: gitDiff.rawContent,
                    enrichedHunks: enrichedHunks,
                    commitHash: gitDiff.commitHash,
                    fileContent: fileContent
                )
            }
        }

        return EnrichedFileData(
            filePath: filePath,
            fileContent: fileContent,
            enrichedDiff: enrichedDiff,
            blameSections: blameData?.sections ?? []
        )
    }

    /// Get enriched diff for staged changes
    public func getEnrichedStagedDiff(includeBlame: Bool = true) async throws -> EnrichedDiff {
        let gitDiff = try await diffAnalyzer.getStagedDiff()

        if !includeBlame {
            return EnrichedDiff.fromGitDiff(gitDiff)
        }

        var enrichedHunks: [EnrichedHunk] = []
        for hunk in gitDiff.hunks {
            let blameInfo = try await getBlameForHunk(hunk)
            enrichedHunks.append(EnrichedHunk(hunk: hunk, blameInfo: blameInfo))
        }

        return EnrichedDiff(
            rawContent: gitDiff.rawContent,
            enrichedHunks: enrichedHunks,
            commitHash: gitDiff.commitHash
        )
    }

    /// Get enriched diff for unstaged changes
    public func getEnrichedUnstagedDiff(includeBlame: Bool = true) async throws -> EnrichedDiff {
        let gitDiff = try await diffAnalyzer.getUnstagedDiff()

        if !includeBlame {
            return EnrichedDiff.fromGitDiff(gitDiff)
        }

        var enrichedHunks: [EnrichedHunk] = []
        for hunk in gitDiff.hunks {
            let blameInfo = try await getBlameForHunk(hunk)
            enrichedHunks.append(EnrichedHunk(hunk: hunk, blameInfo: blameInfo))
        }

        return EnrichedDiff(
            rawContent: gitDiff.rawContent,
            enrichedHunks: enrichedHunks,
            commitHash: gitDiff.commitHash
        )
    }

    // MARK: - Private Helper Methods

    /// Get blame information for lines in a hunk
    private func getBlameForHunk(_ hunk: Hunk) async throws -> [Int: BlameInfo] {
        var blameInfo: [Int: BlameInfo] = [:]

        // Parse the hunk to find which lines we need blame for
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
                // This is an added line - get blame for it
                if let ownership = try await gitRepo.getOwnership(for: hunk.filePath, line: currentNewLine) {
                    blameInfo[currentNewLine] = BlameInfo(
                        author: ownership.author,
                        commitHash: ownership.commitHash,
                        commitDate: ownership.commitDate,
                        summary: ownership.summary,
                        confidence: ownership.confidence
                    )
                }
                currentNewLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                // Removed line - no new line number
                continue
            } else if line.hasPrefix(" ") || (inDiffContent && !line.isEmpty) {
                // Context line - optionally get blame
                // For now, we'll skip context lines to keep it efficient
                currentNewLine += 1
            }
        }

        return blameInfo
    }

    /// Parse raw diff text with optional blame enrichment
    public func parseEnrichedDiff(
        _ diffText: String,
        commitHash: String? = nil,
        includeBlame: Bool = false
    ) async throws -> EnrichedDiff {
        let gitDiff = diffAnalyzer.parseDiffText(diffText, commitHash: commitHash)

        if !includeBlame {
            return EnrichedDiff.fromGitDiff(gitDiff)
        }

        var enrichedHunks: [EnrichedHunk] = []
        for hunk in gitDiff.hunks {
            let blameInfo = try await getBlameForHunk(hunk)
            enrichedHunks.append(EnrichedHunk(hunk: hunk, blameInfo: blameInfo))
        }

        return EnrichedDiff(
            rawContent: gitDiff.rawContent,
            enrichedHunks: enrichedHunks,
            commitHash: commitHash
        )
    }

    // MARK: - Analysis Methods

    /// Get comprehensive statistics about an enriched diff
    public func getEnrichedStatistics(_ diff: EnrichedDiff) -> EnrichedDiffStatistics {
        let basicStats = diffAnalyzer.getDiffStatistics(
            GitDiff(rawContent: diff.rawContent,
                   hunks: diff.enrichedHunks.map(\.hunk),
                   commitHash: diff.commitHash)
        )

        // Collect unique authors from blame info
        var authors = Set<String>()
        for enrichedHunk in diff.enrichedHunks {
            for (_, blame) in enrichedHunk.blameInfo {
                authors.insert(blame.author.email)
            }
        }

        return EnrichedDiffStatistics(
            filesChanged: basicStats.filesChanged,
            linesAdded: basicStats.linesAdded,
            linesRemoved: basicStats.linesRemoved,
            totalHunks: basicStats.totalHunks,
            uniqueAuthors: authors.count,
            authors: Array(authors).sorted()
        )
    }
}

/// Extended statistics for enriched diffs
public struct EnrichedDiffStatistics {
    public let filesChanged: Int
    public let linesAdded: Int
    public let linesRemoved: Int
    public let totalHunks: Int
    public let uniqueAuthors: Int
    public let authors: [String]
}
