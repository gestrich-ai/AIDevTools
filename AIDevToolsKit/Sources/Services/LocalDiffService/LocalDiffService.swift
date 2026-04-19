import GitSDK
import PRRadarModelsService

public struct LocalDiffService: Sendable {
    private let gitClient: GitClient

    public init(gitClient: GitClient = GitClient()) {
        self.gitClient = gitClient
    }

    public func getCombinedDiff(commits: [String], repoPath: String) async throws -> GitDiff {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        guard let newestCommit = commits.first, let oldestCommit = commits.last else {
            return GitDiff(rawContent: "", hunks: [], commitHash: "")
        }

        do {
            let rawDiff = try await gitClient.diff(
                ref1: "\(oldestCommit)^",
                ref2: newestCommit,
                workingDirectory: repoPath
            )
            let commitHash = commits.count == 1 ? newestCommit : "\(oldestCommit)^...\(newestCommit)"
            return GitDiff.fromDiffContent(rawDiff, commitHash: commitHash)
        } catch {
            throw GitOperationsError.diffFailed("Failed to compute combined diff: \(error)")
        }
    }

    public func getDiff(forCommit commit: String, repoPath: String) async throws -> GitDiff {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            let rawDiff = try await gitClient.show(spec: commit, format: "", workingDirectory: repoPath)
            return GitDiff.fromDiffContent(rawDiff, commitHash: commit)
        } catch {
            throw GitOperationsError.diffFailed("Failed to load diff for commit \(commit): \(error)")
        }
    }

    public func getStagedDiff(repoPath: String) async throws -> GitDiff {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            let rawDiff = try await gitClient.diff(cached: true, workingDirectory: repoPath)
            return GitDiff.fromDiffContent(rawDiff, commitHash: "INDEX")
        } catch {
            throw GitOperationsError.diffFailed("Failed to load staged diff: \(error)")
        }
    }

    public func getUnstagedDiff(repoPath: String) async throws -> GitDiff {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            let rawDiff = try await gitClient.diff(ref1: "HEAD", workingDirectory: repoPath)
            return GitDiff.fromDiffContent(rawDiff, commitHash: "WORKTREE")
        } catch {
            throw GitOperationsError.diffFailed("Failed to load unstaged diff: \(error)")
        }
    }

    public func listCommitsMatching(_ pattern: String, repoPath: String) async throws -> [GitCommitSummary] {
        try await gitClient.logGrepAll(pattern, workingDirectory: repoPath).map { entry in
            let subject = entry.body
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return GitCommitSummary(body: entry.body, hash: entry.hash, subject: subject)
        }
    }

    public func listRecentCommits(limit: Int = 20, repoPath: String) async throws -> [GitCommitSummary] {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        return try await gitClient.listRecentCommits(maxCount: limit, workingDirectory: repoPath)
    }
}
