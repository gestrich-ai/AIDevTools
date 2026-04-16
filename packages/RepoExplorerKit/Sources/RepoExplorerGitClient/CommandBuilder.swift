import RepoExplorerCLITools
import Foundation

/// Errors that can occur during GitClient operations
public enum GitClientError: Error, LocalizedError {
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        }
    }
}

/// Builder pattern for constructing CLI commands
public struct CommandBuilder: Sendable {
    private let service: CLIService
    
    public init(service: CLIService = .shared) {
        self.service = service
    }
    
    /// Create a Git command builder
    public func git() -> GitCommandBuilder {
        GitCommandBuilder(service: service)
    }
    
    /// Create a Swift command builder
    public func swift() -> SwiftCommandBuilder {
        SwiftCommandBuilder(service: service)
    }
}

// MARK: - Git Commands

public struct GitCommandBuilder: Sendable {
    private let service: CLIService
    private let command = "/usr/bin/git"
    
    init(service: CLIService) {
        self.service = service
    }
    
    /// Execute git status
    public func status(
        in directory: String,
        porcelain: Bool = false
    ) async throws -> ExecutionResult {
        var args = ["status"]
        if porcelain {
            args.append("--porcelain")
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Get full repository status including rebase state
    public func getRepositoryStatus(
        in directory: String
    ) async throws -> GitRepositoryStatus {
        let porcelainResult = try await status(in: directory, porcelain: true)
        let parser = GitStatusParser()
        return try await parser.parseStatus(
            porcelainOutput: porcelainResult.stdout,
            repoPath: directory
        )
    }
    
    /// Execute git blame
    public func blame(
        file: String,
        line: Int? = nil,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["blame", "--line-porcelain"]
        
        if let line {
            args.append(contentsOf: ["-L", "\(line),\(line)"])
        }
        
        args.append(file)
        
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }
    
    /// Execute git show to get file content at specific commit
    public func show(
        file: String,
        at commit: String? = nil,
        in directory: String
    ) async throws -> ExecutionResult {
        var target: String
        if let commit {
            target = "\(commit):\(file)"
        } else {
            target = "HEAD:\(file)"
        }
        
        return try await service.execute(
            command: command,
            arguments: ["show", target],
            workingDirectory: directory
        )
    }
    
    /// Execute git log
    public func log(
        file: String? = nil,
        format: String? = nil,
        limit: Int? = nil,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["log"]
        
        if let limit {
            args.append("-\(limit)")
        }
        
        if let format {
            args.append("--pretty=format:\(format)")
        }
        
        if let file {
            args.append(contentsOf: ["--", file])
        }
        
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }
    
    /// Execute git checkout
    public func checkout(
        _ ref: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["checkout", ref],
            workingDirectory: directory
        )
    }
    
    /// Execute git fetch
    public func fetch(
        remote: String = "origin",
        ref: String? = nil,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["fetch", remote]
        if let ref {
            args.append(ref)
        }
        
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }
    
    /// Execute arbitrary git command
    public func custom(
        arguments: [String],
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: arguments,
            workingDirectory: directory
        )
    }

    // MARK: - Worktree Operations

    /// List worktrees
    public func worktreeList(
        porcelain: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["worktree", "list"]
        if porcelain {
            args.append("--porcelain")
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Add a new worktree
    public func worktreeAdd(
        path: String,
        branch: String? = nil,
        newBranch: String? = nil,
        baseBranch: String? = nil,
        detach: Bool = false,
        force: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["worktree", "add"]

        if detach {
            args.append("--detach")
        }

        if force {
            args.append("--force")
        }

        if let newBranch {
            args.append(contentsOf: ["-b", newBranch])
        }

        args.append(path)

        if let baseBranch {
            args.append(baseBranch)
        } else if let branch {
            args.append(branch)
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Remove a worktree
    public func worktreeRemove(
        path: String,
        force: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["worktree", "remove", path]
        if force {
            args.append("--force")
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Prune worktrees
    public func worktreePrune(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["worktree", "prune"],
            workingDirectory: directory
        )
    }

    // MARK: - Branch Operations (Single Commands)

    /// Check if a local branch exists
    public func branchExists(
        branch: String,
        in directory: String
    ) async throws -> Bool {
        let result = try await service.execute(
            command: command,
            arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            workingDirectory: directory
        )
        return result.isSuccess
    }

    /// Check if a remote tracking branch exists
    public func remoteTrackingBranchExists(
        branch: String,
        remote: String = "origin",
        in directory: String
    ) async throws -> Bool {
        let result = try await service.execute(
            command: command,
            arguments: ["show-ref", "--verify", "--quiet", "refs/remotes/\(remote)/\(branch)"],
            workingDirectory: directory
        )
        return result.isSuccess
    }

    /// Delete a branch forcefully (bypasses safety checks)
    public func deleteBranch(
        _ branch: String,
        force: Bool = true,
        in directory: String
    ) async throws -> ExecutionResult {
        let args = force ? ["branch", "-D", branch] : ["branch", "-d", branch]
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Delete remote tracking branch
    public func deleteRemoteTrackingBranch(
        _ branch: String,
        remote: String = "origin",
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["branch", "-r", "-D", "\(remote)/\(branch)"],
            workingDirectory: directory
        )
    }

    // MARK: - Repository Maintenance (Single Commands)

    /// Update a ref directly (low-level operation)
    public func updateRef(
        ref: String,
        delete: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        let args = delete ? ["update-ref", "-d", ref] : ["update-ref", ref]
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Expire reflog entries
    public func reflogExpire(
        expireDate: String = "now",
        all: Bool = true,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["reflog", "expire", "--expire=\(expireDate)"]
        if all {
            args.append("--all")
        }
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Garbage collect repository
    public func gc(
        prune: String? = "now",
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["gc"]
        if let prune {
            args.append("--prune=\(prune)")
        }
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    // MARK: - Remote Operations

    /// List remotes
    public func remote(
        verbose: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["remote"]
        if verbose {
            args.append("-v")
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Update remotes
    public func remoteUpdate(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["remote", "update"],
            workingDirectory: directory
        )
    }

    // MARK: - Branch Operations

    /// Create and checkout a new branch
    public func createBranch(
        _ branchName: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["checkout", "-b", branchName],
            workingDirectory: directory
        )
    }

    /// Get current branch name
    public func currentBranch(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["branch", "--show-current"],
            workingDirectory: directory
        )
    }

    /// Get current HEAD reference (works for both branch and detached HEAD)
    public func getCurrentRef(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["rev-parse", "--short", "HEAD"],
            workingDirectory: directory
        )
    }

    /// Check if HEAD is detached
    public func isDetachedHead(
        in directory: String
    ) async throws -> Bool {
        let result = try await currentBranch(in: directory)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Get upstream branch
    public func upstreamBranch(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            workingDirectory: directory
        )
    }

    /// List branches with detailed information
    public func listBranches(
        remote: Bool = false,
        all: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["branch"]

        if all {
            args.append("--all")
        } else if remote {
            args.append("--remote")
        }

        args.append(contentsOf: [
            "--format=%(refname:short)|%(upstream:short)|%(HEAD)|%(objectname:short)|%(committerdate:iso8601)|%(authorname)"
        ])

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Rename a branch
    public func renameBranch(
        oldName: String,
        newName: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["branch", "-m", oldName, newName],
            workingDirectory: directory
        )
    }

    /// Set upstream branch for tracking
    public func setUpstreamBranch(
        branch: String,
        upstream: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["branch", "--set-upstream-to=\(upstream)", branch],
            workingDirectory: directory
        )
    }

    /// Get commit information for a branch
    public func getBranchCommitInfo(
        branch: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: [
                "log",
                "-1",
                "--format=%H|%h|%s|%an|%ae|%at|%cn|%ce|%ct",
                branch
            ],
            workingDirectory: directory
        )
    }

    /// Get ahead/behind tracking information for a branch
    public func getBranchTrackingInfo(
        branch: String,
        upstream: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["rev-list", "--left-right", "--count", "\(upstream)...\(branch)"],
            workingDirectory: directory
        )
    }

    /// Check if a branch has been merged into another branch
    /// Returns true if all commits from sourceBranch are in targetBranch
    public func isBranchMerged(
        branch: String,
        into targetBranch: String = "main",
        in directory: String
    ) async throws -> Bool {
        // Use git branch --merged to check if branch is in the merged list
        let result = try await service.execute(
            command: command,
            arguments: ["branch", "--merged", targetBranch],
            workingDirectory: directory
        )

        guard result.isSuccess else {
            return false
        }

        // Check if the branch name appears in the merged list
        let mergedBranches = result.stdout.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }

        return mergedBranches.contains(branch)
    }

    // MARK: - Branch Operations (Typed Returns)

    /// List all branches with parsed metadata
    public func getBranches(
        all: Bool = false,
        in directory: String
    ) async throws -> [BranchListItem] {
        let result = try await listBranches(all: all, in: directory)

        guard result.isSuccess else {
            return []
        }

        return parseBranchList(result.stdout)
    }

    /// Get tracking info (ahead/behind) for a branch - returns typed data
    public func getTrackingInfo(
        branch: String,
        upstream: String,
        in directory: String
    ) async throws -> TrackingInfo {
        let result = try await getBranchTrackingInfo(
            branch: branch,
            upstream: upstream,
            in: directory
        )

        guard result.isSuccess else {
            return TrackingInfo(ahead: 0, behind: 0)
        }

        let parts = result.stdout.split(separator: "\t")
        guard parts.count >= 2 else {
            return TrackingInfo(ahead: 0, behind: 0)
        }

        let behind = Int(parts[0]) ?? 0  // Left side (upstream ahead)
        let ahead = Int(parts[1]) ?? 0   // Right side (branch ahead)

        return TrackingInfo(ahead: ahead, behind: behind)
    }

    /// Get commit info for a branch - returns typed data
    public func getCommitInfo(
        branch: String,
        in directory: String
    ) async throws -> CommitInfo? {
        let result = try await getBranchCommitInfo(branch: branch, in: directory)

        guard result.isSuccess else {
            return nil
        }

        return parseCommitInfo(result.stdout)
    }

    /// Get commit count between two refs - returns Int
    public func getCommitCount(
        from: String,
        to: String,
        in directory: String
    ) async throws -> Int {
        let result = try await custom(
            arguments: ["rev-list", "--count", "\(from)..\(to)"],
            in: directory
        )

        guard result.isSuccess else {
            return 0
        }

        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Get diff stats - returns typed data
    public func getDiffStats(
        from: String,
        to: String,
        in directory: String
    ) async throws -> DiffStats {
        let result = try await diff(from: from, to: to, stat: true, in: directory)

        guard result.isSuccess else {
            return DiffStats(filesChanged: 0)
        }

        return parseDiffStats(result.stdout)
    }

    /// Parse merge result - returns typed data
    public func parseMergeResult(_ result: ExecutionResult) -> GitMergeResult {
        if result.isSuccess {
            return GitMergeResult(success: true)
        }

        // Check for conflicts
        if result.stderr.contains("CONFLICT") {
            let conflicts = parseConflictFiles(result.stderr)
            return GitMergeResult(
                success: false,
                hasConflicts: true,
                conflictFiles: conflicts,
                errorMessage: result.stderr
            )
        }

        return GitMergeResult(
            success: false,
            hasConflicts: false,
            errorMessage: result.stderr
        )
    }

    // MARK: - Private Parsing Helpers

    /// Parse branch list output
    private func parseBranchList(_ output: String) -> [BranchListItem] {
        let lines = output.split(separator: "\n")
        var branches: [BranchListItem] = []

        for line in lines {
            // Split without trimming first to preserve empty strings
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 5 else { continue }

            let refName = parts[0]
            let upstream = parts[1].isEmpty ? nil : parts[1]
            let isHead = parts[2] == "*"
            let commitHash = parts[3]
            let commitDate = parseISO8601Date(parts[4])

            let isRemote = refName.hasPrefix("remotes/")

            branches.append(BranchListItem(
                refName: refName,
                upstream: upstream,
                isHead: isHead,
                commitHash: commitHash,
                commitDate: commitDate,
                isRemote: isRemote
            ))
        }

        return branches
    }

    /// Parse commit info from log output
    private func parseCommitInfo(_ output: String) -> CommitInfo? {
        let parts = output.split(separator: "|")
        guard parts.count >= 9 else { return nil }

        return CommitInfo(
            hash: String(parts[0]),
            shortHash: String(parts[1]),
            message: String(parts[2]),
            authorName: String(parts[3]),
            authorEmail: String(parts[4]),
            authorTimestamp: Int(parts[5]) ?? 0,
            committerName: String(parts[6]),
            committerEmail: String(parts[7]),
            committerTimestamp: Int(parts[8]) ?? 0
        )
    }

    /// Parse diff --stat output
    private func parseDiffStats(_ output: String) -> DiffStats {
        let lines = output.split(separator: "\n")
        guard let lastLine = lines.last else {
            return DiffStats(filesChanged: 0)
        }

        // Last line: "3 files changed, 45 insertions(+), 12 deletions(-)"
        let parts = lastLine.split(separator: ",")

        var filesChanged = 0
        var insertions = 0
        var deletions = 0

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let numbers = trimmed.split(separator: " ").compactMap { Int($0) }

            if trimmed.contains("file") {
                filesChanged = numbers.first ?? 0
            } else if trimmed.contains("insertion") {
                insertions = numbers.first ?? 0
            } else if trimmed.contains("deletion") {
                deletions = numbers.first ?? 0
            }
        }

        return DiffStats(filesChanged: filesChanged, insertions: insertions, deletions: deletions)
    }

    /// Parse conflict files from merge error output
    private func parseConflictFiles(_ output: String) -> [String] {
        let lines = output.split(separator: "\n")
        var conflicts: [String] = []

        for line in lines {
            if line.contains("CONFLICT") {
                // Example: "CONFLICT (content): Merge conflict in file.txt"
                let parts = line.split(separator: " ")
                if let inIndex = parts.firstIndex(of: "in"), inIndex + 1 < parts.count {
                    conflicts.append(String(parts[inIndex + 1]))
                }
            }
        }

        return conflicts
    }

    /// Parse ISO 8601 date
    private func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    /// Merge a branch into current branch
    public func merge(
        branch: String,
        fastForward: Bool = true,
        noCommit: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["merge"]

        if fastForward {
            args.append("--ff")
        } else {
            args.append("--no-ff")
        }

        if noCommit {
            args.append("--no-commit")
        }

        args.append(branch)

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Pull from remote
    public func pull(
        remote: String = "origin",
        branch: String? = nil,
        rebase: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["pull"]

        if rebase {
            args.append("--rebase")
        }

        args.append(remote)

        if let branch {
            args.append(branch)
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    // MARK: - Commit Operations

    /// Add files to staging
    public func add(
        files: [String] = [],
        all: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["add"]

        if all {
            args.append("-A")
        } else {
            args.append(contentsOf: files)
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Unstage files (reset from staging area)
    public func unstage(
        files: [String],
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["reset", "HEAD", "--"]
        args.append(contentsOf: files)

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Stage a specific hunk to the staging area
    /// Uses git apply --cached to selectively stage changes
    public func stageHunk(
        _ hunk: Hunk,
        in directory: String
    ) async throws -> ExecutionResult {
        // Build a clean patch from the hunk
        // The hunk.content might include extra lines from subsequent files,
        // so we need to extract just the parts we need
        var patchLines: [String] = []

        // Add file header
        patchLines.append("diff --git a/\(hunk.filePath) b/\(hunk.filePath)")
        patchLines.append("--- a/\(hunk.filePath)")
        patchLines.append("+++ b/\(hunk.filePath)")

        // Extract just this hunk's content (header + diff lines)
        let contentLines = hunk.content.components(separatedBy: .newlines)
        var inHunk = false
        var linesAdded = 0
        let expectedLines = hunk.oldLength + hunk.newLength // Rough estimate

        for line in contentLines {
            if line.hasPrefix("@@") && line.contains("-\(hunk.oldStart)") {
                inHunk = true
                patchLines.append(line)
            } else if inHunk {
                // Stop if we hit another hunk marker or file header
                if line.hasPrefix("@@") || line.hasPrefix("diff --git") {
                    break
                }
                patchLines.append(line)
                linesAdded += 1

                // Stop if we've collected enough lines for this hunk
                if linesAdded >= expectedLines {
                    break
                }
            }
        }

        let patchContent = patchLines.joined(separator: "\n") + "\n"

        // Write patch to temporary file
        let tempDir = NSTemporaryDirectory()
        let patchPath = "\(tempDir)stage_hunk_\(UUID().uuidString).patch"

        do {
            try patchContent.write(toFile: patchPath, atomically: true, encoding: .utf8)

            // Apply the patch to the staging area
            let result = try await service.execute(
                command: command,
                arguments: ["apply", "--cached", patchPath],
                workingDirectory: directory
            )

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: patchPath)

            return result
        } catch {
            // Clean up temp file on error
            try? FileManager.default.removeItem(atPath: patchPath)
            throw error
        }
    }

    /// Unstage a specific hunk from the staging area
    /// Uses git apply --reverse --cached to selectively unstage changes
    public func unstageHunk(
        _ hunk: Hunk,
        in directory: String
    ) async throws -> ExecutionResult {
        // Build a clean patch from the hunk
        // The hunk.content might include extra lines from subsequent files,
        // so we need to extract just the parts we need
        var patchLines: [String] = []

        // Add file header
        patchLines.append("diff --git a/\(hunk.filePath) b/\(hunk.filePath)")
        patchLines.append("--- a/\(hunk.filePath)")
        patchLines.append("+++ b/\(hunk.filePath)")

        // Extract just this hunk's content (header + diff lines)
        let contentLines = hunk.content.components(separatedBy: .newlines)
        var inHunk = false
        var linesAdded = 0
        let expectedLines = hunk.oldLength + hunk.newLength // Rough estimate

        for line in contentLines {
            if line.hasPrefix("@@") && line.contains("-\(hunk.oldStart)") {
                inHunk = true
                patchLines.append(line)
            } else if inHunk {
                // Stop if we hit another hunk marker or file header
                if line.hasPrefix("@@") || line.hasPrefix("diff --git") {
                    break
                }
                patchLines.append(line)
                linesAdded += 1

                // Stop if we've collected enough lines for this hunk
                if linesAdded >= expectedLines {
                    break
                }
            }
        }

        let patchContent = patchLines.joined(separator: "\n") + "\n"

        // Write patch to temporary file
        let tempDir = NSTemporaryDirectory()
        let patchPath = "\(tempDir)unstage_hunk_\(UUID().uuidString).patch"

        do {
            try patchContent.write(toFile: patchPath, atomically: true, encoding: .utf8)

            // Apply the patch in reverse to the staging area
            let result = try await service.execute(
                command: command,
                arguments: ["apply", "--reverse", "--cached", patchPath],
                workingDirectory: directory
            )

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: patchPath)

            return result
        } catch {
            // Clean up temp file on error
            try? FileManager.default.removeItem(atPath: patchPath)
            throw error
        }
    }

    /// Commit changes
    public func commit(
        message: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["commit", "-m", message],
            workingDirectory: directory
        )
    }

    /// Amend the last commit with a new message
    public func commitAmend(
        message: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["commit", "--amend", "-m", message],
            workingDirectory: directory
        )
    }

    /// Push branch with comprehensive options
    ///
    /// - Parameters:
    ///   - remote: Remote name (default: "origin")
    ///   - branch: Local branch to push (optional)
    ///   - remoteBranch: Destination ref on remote (optional, defaults to same as local branch)
    ///   - setUpstream: Set upstream tracking reference
    ///   - force: Force push (DANGEROUS - use forceWithLease instead)
    ///   - forceWithLease: Safe force push - only pushes if remote hasn't changed
    ///   - tags: Push all tags
    ///   - recurseSubmodules: Recurse into submodules ("check" or "on-demand")
    ///   - noVerify: Skip pre-push hooks
    ///   - directory: Repository path
    /// - Throws: Error if force and forceWithLease are both true
    public func push(
        remote: String = "origin",
        branch: String? = nil,
        remoteBranch: String? = nil,
        setUpstream: Bool = false,
        force: Bool = false,
        forceWithLease: Bool = false,
        tags: Bool = false,
        recurseSubmodules: String? = nil,
        noVerify: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        // Validation: force and forceWithLease are mutually exclusive
        if force && forceWithLease {
            throw GitClientError.invalidArguments("force and forceWithLease cannot both be true")
        }

        // Validation: recurseSubmodules must be "check" or "on-demand"
        if let recurse = recurseSubmodules {
            guard recurse == "check" || recurse == "on-demand" else {
                throw GitClientError.invalidArguments("recurseSubmodules must be 'check' or 'on-demand', got '\(recurse)'")
            }
        }

        var args = ["push"]

        // Force options (mutually exclusive)
        if forceWithLease {
            args.append("--force-with-lease")
        } else if force {
            args.append("--force")
        }

        // Push all tags
        if tags {
            args.append("--tags")
        }

        // Recurse into submodules
        if let recurse = recurseSubmodules {
            args.append("--recurse-submodules=\(recurse)")
        }

        // Skip hooks
        if noVerify {
            args.append("--no-verify")
        }

        // Set upstream tracking
        if setUpstream {
            args.append("--set-upstream")
        }

        // Remote
        args.append(remote)

        // Refspec: local:remote
        if let branch {
            if let remoteBranch {
                // Push to different remote branch: local:remote
                args.append("\(branch):\(remoteBranch)")
            } else {
                // Push to same-named branch
                args.append(branch)
            }
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    // MARK: - Diff Operations

    /// Get diff between commits or branches
    public func diff(
        from: String? = nil,
        to: String? = nil,
        stat: Bool = false,
        numstat: Bool = false,
        nameStatus: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["diff"]

        if stat {
            args.append("--stat")
        }

        if numstat {
            args.append("--numstat")
        }

        if nameStatus {
            args.append("--name-status")
        }

        if let from {
            if let to {
                args.append("\(from)...\(to)")
            } else {
                args.append(from)
            }
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Get staged changes diff (what would be committed)
    public func diffStaged(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["diff", "--cached"],
            workingDirectory: directory
        )
    }

    /// Get unstaged changes diff (working directory changes)
    public func diffUnstaged(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["diff"],
            workingDirectory: directory
        )
    }

    /// Comprehensive file information from git status
    public struct FileStatusInfo: Sendable, Equatable {
        public let filePath: String
        public let status: FileChangeStatus
        public let isStaged: Bool
        public let renamedFrom: String?

        public init(filePath: String, status: FileChangeStatus, isStaged: Bool, renamedFrom: String? = nil) {
            self.filePath = filePath
            self.status = status
            self.isStaged = isStaged
            self.renamedFrom = renamedFrom
        }
    }

    public enum FileChangeStatus: String, Sendable, Equatable {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case untracked = "?"
        case ignored = "!"
        case typeChanged = "T"

        public var displayName: String {
            switch self {
            case .modified: return "Modified"
            case .added: return "Added"
            case .deleted: return "Deleted"
            case .renamed: return "Renamed"
            case .copied: return "Copied"
            case .untracked: return "Untracked"
            case .ignored: return "Ignored"
            case .typeChanged: return "Type Changed"
            }
        }

        public var letter: String {
            rawValue
        }
    }

    /// Get comprehensive file status including untracked, deleted, and renamed files
    public func getFileStatuses(
        in directory: String
    ) async throws -> [FileStatusInfo] {
        // Use --porcelain=v1 for consistent parsing
        let result = try await service.execute(
            command: command,
            arguments: ["status", "--porcelain=v1", "-uall"],
            workingDirectory: directory
        )

        guard result.isSuccess else {
            return []
        }

        var fileInfos: [FileStatusInfo] = []
        let lines = result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            // Format: XY PATH or XY PATH -> RENAMED_FROM for renames
            guard line.count >= 3 else { continue }

            let indexChar = String(line.prefix(1))
            let workingChar = String(line.dropFirst().prefix(1))
            let pathPart = String(line.dropFirst(3))

            // Handle rename detection (R  new -> old)
            var filePath = pathPart
            var renamedFrom: String?

            if let renameRange = pathPart.range(of: " -> ") {
                renamedFrom = String(pathPart[pathPart.startIndex..<renameRange.lowerBound])
                filePath = String(pathPart[renameRange.upperBound...])
            }

            // Strip surrounding quotes (git adds quotes for paths with spaces)
            filePath = stripQuotes(filePath)
            if let renamed = renamedFrom {
                renamedFrom = stripQuotes(renamed)
            }

            // Parse staged changes (index status)
            if let status = parseStatusChar(indexChar), indexChar != " " && indexChar != "?" {
                fileInfos.append(FileStatusInfo(
                    filePath: filePath,
                    status: status,
                    isStaged: true,
                    renamedFrom: renamedFrom
                ))
            }

            // Parse unstaged changes (working tree status)
            if let status = parseStatusChar(workingChar), workingChar != " " {
                fileInfos.append(FileStatusInfo(
                    filePath: filePath,
                    status: status,
                    isStaged: false,
                    renamedFrom: renamedFrom
                ))
            }
        }

        return fileInfos
    }

    /// Strip surrounding quotes from a file path if present
    private func stripQuotes(_ path: String) -> String {
        var result = path
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    private func parseStatusChar(_ char: String) -> FileChangeStatus? {
        switch char {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "?": return .untracked
        case "!": return .ignored
        case "T": return .typeChanged
        default: return nil
        }
    }

    /// Get working directory files with merged staged/unstaged status
    /// This merges files that have dual status (e.g., AD = Added in index, Deleted in working tree)
    public func getWorkingDirectoryFiles(
        in directory: String,
        filter: WorkingDirectoryFilter = .all
    ) async throws -> [WorkingDirectoryFile] {
        let fileStatuses = try await getFileStatuses(in: directory)

        // Group by file path
        let grouped = Dictionary(grouping: fileStatuses, by: { $0.filePath })

        // Merge staged and unstaged statuses for each file
        var workingFiles: [WorkingDirectoryFile] = []

        for (filePath, statuses) in grouped {
            let stagedStatus = statuses.first(where: \.isStaged)?.status
            let unstagedStatus = statuses.first(where: { !$0.isStaged })?.status
            let renamedFrom = statuses.first(where: { $0.renamedFrom != nil })?.renamedFrom

            workingFiles.append(WorkingDirectoryFile(
                filePath: filePath,
                stagedStatus: stagedStatus,
                unstagedStatus: unstagedStatus,
                renamedFrom: renamedFrom
            ))
        }

        // Apply filter
        let filteredFiles: [WorkingDirectoryFile]
        switch filter {
        case .all:
            filteredFiles = workingFiles
        case .staged:
            filteredFiles = workingFiles.filter(\.isStaged)
        case .unstaged:
            filteredFiles = workingFiles.filter(\.hasUnstagedChanges)
        }

        return filteredFiles.sorted { $0.filePath < $1.filePath }
    }

    // MARK: - Repository State Operations

    /// Reset repository state
    public func reset(
        mode: ResetMode = .hard,
        target: String = "HEAD",
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["reset", mode.rawValue, target],
            workingDirectory: directory
        )
    }

    /// Clean untracked files
    public func clean(
        force: Bool = false,
        directories: Bool = false,
        ignored: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["clean"]

        if force {
            args.append("-f")
            if directories {
                args.append("-f") // -ff for directories
            }
        }

        if directories {
            args.append("-d")
            if ignored {
                args.append("-d") // -dd for ignored directories
            }
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    // MARK: - Counting Operations

    /// Count commits between refs
    public func revListCount(
        from: String,
        to: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["rev-list", "--count", "\(from)..\(to)"],
            workingDirectory: directory
        )
    }

    /// Check if ref exists
    public func revParse(
        ref: String,
        verify: Bool = false,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["rev-parse"]
        if verify {
            args.append("--verify")
        }
        args.append(ref)

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// List remote refs
    public func lsRemote(
        remote: String = "origin",
        heads: Bool = false,
        branch: String? = nil,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["ls-remote"]

        if heads {
            args.append("--heads")
        }

        args.append(remote)

        if let branch {
            args.append(branch)
        }

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    public enum ResetMode: String {
        case soft = "--soft"
        case mixed = "--mixed"
        case hard = "--hard"
    }

    // MARK: - Rebase Operations

    /// Get commit log for interactive rebase
    public func getCommits(
        baseBranch: String = "origin/main",
        in directory: String
    ) async throws -> ExecutionResult {
        // First check if HEAD is detached and if base branch exists
        let revParseResult = try await service.execute(
            command: command,
            arguments: ["rev-parse", "--verify", baseBranch],
            workingDirectory: directory
        )

        // If base branch doesn't exist, return helpful error
        guard revParseResult.isSuccess else {
            return ExecutionResult(
                exitCode: 1,
                stdout: "",
                stderr: "Base branch '\(baseBranch)' does not exist. Try 'git fetch' or use a different base branch.",
                duration: 0
            )
        }

        let args = [
            "log",
            "--oneline",
            "--format=%H|%h|%s|%an|%at",
            "\(baseBranch)..HEAD"
        ]

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Get last N commits for interactive rebase
    public func getLastCommits(
        count: Int,
        in directory: String
    ) async throws -> ExecutionResult {
        let args = [
            "log",
            "--oneline",
            "--format=%H|%h|%s|%an|%at",
            "-\(count)"
        ]

        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }

    /// Start interactive rebase
    public func rebaseInteractive(
        onto: String,
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["rebase", "-i", onto],
            workingDirectory: directory,
            environment: ["GIT_SEQUENCE_EDITOR": "cat"]
        )
    }

    /// Continue rebase after resolving conflicts
    public func rebaseContinue(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["rebase", "--continue"],
            workingDirectory: directory,
            environment: ["GIT_EDITOR": "true"]
        )
    }

    /// Abort rebase
    public func rebaseAbort(
        in directory: String
    ) async throws -> ExecutionResult {
        try await service.execute(
            command: command,
            arguments: ["rebase", "--abort"],
            workingDirectory: directory
        )
    }

    /// Simple rebase onto a branch (non-interactive)
    /// First fetches the branch, then rebases onto FETCH_HEAD
    public func rebaseOntoBranch(
        branch: String,
        in directory: String
    ) async throws -> ExecutionResult {
        // Parse branch format: "origin/develop" -> remote="origin", ref="develop"
        let components = branch.split(separator: "/", maxSplits: 1)
        let remote = components.first.map(String.init) ?? "origin"
        let ref = components.count > 1 ? String(components[1]) : branch

        // Fetch the branch
        let fetchResult = try await fetch(remote: remote, ref: ref, in: directory)
        guard fetchResult.isSuccess else {
            return fetchResult
        }

        // Rebase onto FETCH_HEAD
        return try await service.execute(
            command: command,
            arguments: ["rebase", "FETCH_HEAD"],
            workingDirectory: directory
        )
    }

    /// Check rebase status
    public func rebaseStatus(
        in directory: String
    ) throws -> Bool {
        let rebaseDir = "\(directory)/.git/rebase-merge"
        return FileManager.default.fileExists(atPath: rebaseDir)
    }

    /// Edit rebase todo file
    public func editRebaseTodo(
        entries: [RebaseCommitEntry],
        in directory: String
    ) throws {
        let rebaseTodoPath = "\(directory)/.git/rebase-merge/git-rebase-todo"
        var lines: [String] = []

        for entry in entries.reversed() {
            let action = entry.action.rawValue
            let hash = entry.commit.shortHash
            let message = entry.editedMessage ?? entry.commit.message
            lines.append("\(action) \(hash) \(message)")
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(toFile: rebaseTodoPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Swift Commands

public struct SwiftCommandBuilder: Sendable {
    private let service: CLIService
    private let command = "/usr/bin/swift"
    
    init(service: CLIService) {
        self.service = service
    }
    
    /// Execute swift build
    public func build(
        configuration: BuildConfiguration = .debug,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["build"]
        args.append(contentsOf: ["-c", configuration.rawValue])
        
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }
    
    /// Execute swift test
    public func test(
        filter: String? = nil,
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["test"]
        
        if let filter {
            args.append(contentsOf: ["--filter", filter])
        }
        
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }
    
    /// Execute swift package commands
    public func package(
        subcommand: String,
        arguments: [String] = [],
        in directory: String
    ) async throws -> ExecutionResult {
        var args = ["package", subcommand]
        args.append(contentsOf: arguments)
        
        return try await service.execute(
            command: command,
            arguments: args,
            workingDirectory: directory
        )
    }
    
    public enum BuildConfiguration: String {
        case debug
        case release
    }
}
