import GitSDK
import GitDiffModelsService

public struct LocalDiffService: Sendable {
    private let emptyTreeHash = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    private let gitClient: GitClient

    public init(gitClient: GitClient = GitClient()) {
        self.gitClient = gitClient
    }

    public func getCombinedDiff(commits: [String], repoPath: String) async throws -> GitDiff {
        try await ensureGitRepository(at: repoPath)
        guard let newestCommit = commits.first, let oldestCommit = commits.last else {
            return GitDiff(rawContent: "", hunks: [], commitHash: "")
        }

        return try await loadDiff(
            for: repoPath,
            failurePrefix: "Failed to compute combined diff"
        ) {
            let baseRef = try await combinedDiffBaseReference(for: oldestCommit, repoPath: repoPath)
            let rawDiff = try await gitClient.diff(
                ref1: baseRef,
                ref2: newestCommit,
                workingDirectory: repoPath
            )
            let commitHash = commits.count == 1 ? newestCommit : "\(baseRef)...\(newestCommit)"
            return GitDiff.fromDiffContent(rawDiff, commitHash: commitHash)
        }
    }

    public func getDiff(forCommit commit: String, repoPath: String) async throws -> GitDiff {
        try await ensureGitRepository(at: repoPath)
        return try await loadDiff(
            for: repoPath,
            failurePrefix: "Failed to load diff for commit \(commit)"
        ) {
            let rawDiff = try await gitClient.show(spec: commit, format: "", workingDirectory: repoPath)
            return GitDiff.fromDiffContent(rawDiff, commitHash: commit)
        }
    }

    public func getStagedDiff(repoPath: String) async throws -> GitDiff {
        try await ensureGitRepository(at: repoPath)
        return try await loadDiff(
            for: repoPath,
            failurePrefix: "Failed to load staged diff"
        ) {
            let rawDiff = try await gitClient.diff(cached: true, workingDirectory: repoPath)
            return GitDiff.fromDiffContent(rawDiff, commitHash: "INDEX")
        }
    }

    public func getUnstagedDiff(repoPath: String) async throws -> GitDiff {
        try await ensureGitRepository(at: repoPath)
        return try await loadDiff(
            for: repoPath,
            failurePrefix: "Failed to load unstaged diff"
        ) {
            let rawDiff = try await gitClient.diff(ref1: "HEAD", workingDirectory: repoPath)
            return GitDiff.fromDiffContent(rawDiff, commitHash: "WORKTREE")
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

    private func combinedDiffBaseReference(for oldestCommit: String, repoPath: String) async throws -> String {
        do {
            _ = try await gitClient.catFile(type: true, object: "\(oldestCommit)^", workingDirectory: repoPath)
            return "\(oldestCommit)^"
        } catch {
            return emptyTreeHash
        }
    }

    private func ensureGitRepository(at repoPath: String) async throws {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
    }

    private func loadDiff(
        for repoPath: String,
        failurePrefix: String,
        operation: () async throws -> GitDiff
    ) async throws -> GitDiff {
        do {
            return try await operation()
        } catch {
            throw GitOperationsError.diffFailed("\(failurePrefix): \(error)")
        }
    }
}
