import Foundation

/// Parses git status and rebase state information
public struct GitStatusParser: Sendable {
    public init() {}

    /// Parse git status --porcelain output and combine with rebase state
    public func parseStatus(
        porcelainOutput: String,
        repoPath: String
    ) async throws -> GitRepositoryStatus {
        // Parse file statuses from porcelain output
        let files = parseFileStatuses(from: porcelainOutput)

        // Get branch/detached head info
        let (branch, detachedHead) = try await getBranchInfo(repoPath: repoPath)

        // Check for rebase state
        let rebaseState = try await getRebaseState(repoPath: repoPath, files: files)

        return GitRepositoryStatus(
            branch: branch,
            detachedHead: detachedHead,
            rebaseState: rebaseState,
            files: files
        )
    }

    /// Parse porcelain format file statuses
    private func parseFileStatuses(from output: String) -> [GitFileStatus] {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        return lines.compactMap { line in
            guard line.count >= 4 else { return nil }

            let indexChar = line[line.startIndex]
            let workingTreeChar = line[line.index(after: line.startIndex)]
            let path = String(line.dropFirst(3))

            let indexStatus = parseStatusCode(String(indexChar))
            let workingTreeStatus = parseStatusCode(String(workingTreeChar))

            return GitFileStatus(
                path: path,
                indexStatus: indexStatus,
                workingTreeStatus: workingTreeStatus
            )
        }
    }

    /// Parse single character status code
    private func parseStatusCode(_ code: String) -> FileStatusCode {
        // Check for special conflict markers
        if code == "U" {
            return .bothModified
        }

        return FileStatusCode(rawValue: code) ?? .unmodified
    }

    /// Get current branch or detached HEAD info
    private func getBranchInfo(repoPath: String) async throws -> (branch: String?, detachedHead: String?) {
        let gitBuilder = CommandBuilder().git()

        // Try to get current branch
        let branchResult = try await gitBuilder.currentBranch(in: repoPath)
        let branchName = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if branchName.isEmpty {
            // Detached HEAD - get short SHA
            let refResult = try await gitBuilder.getCurrentRef(in: repoPath)
            let sha = refResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, sha)
        } else {
            return (branchName, nil)
        }
    }

    /// Check if repository is in rebase state and parse details
    private func getRebaseState(
        repoPath: String,
        files: [GitFileStatus]
    ) throws -> RebaseState? {
        let rebaseMergePath = "\(repoPath)/.git/rebase-merge"
        let rebaseApplyPath = "\(repoPath)/.git/rebase-apply"

        let fileManager = FileManager.default

        // Check for interactive rebase (rebase-merge)
        if fileManager.fileExists(atPath: rebaseMergePath) {
            return try parseRebaseMergeState(rebasePath: rebaseMergePath, files: files)
        }

        // Check for non-interactive rebase (rebase-apply)
        if fileManager.fileExists(atPath: rebaseApplyPath) {
            return try parseRebaseApplyState(rebasePath: rebaseApplyPath, files: files)
        }

        return nil
    }

    /// Parse interactive rebase state from rebase-merge directory
    private func parseRebaseMergeState(
        rebasePath: String,
        files: [GitFileStatus]
    ) throws -> RebaseState {
        let headNamePath = "\(rebasePath)/head-name"
        let ontoPath = "\(rebasePath)/onto"
        let msgnumPath = "\(rebasePath)/msgnum"
        let endPath = "\(rebasePath)/end"

        let branchName = try readFile(at: headNamePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "")

        let ontoCommit = try readFile(at: ontoPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let currentStep = Int(try readFile(at: msgnumPath).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let totalSteps = Int(try readFile(at: endPath).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Extract conflicted files
        let conflicts = files
            .filter(\.hasConflict)
            .map(\.path)

        return RebaseState(
            branchName: branchName,
            ontoCommit: ontoCommit,
            currentStep: currentStep,
            totalSteps: totalSteps,
            conflicts: conflicts
        )
    }

    /// Parse non-interactive rebase state from rebase-apply directory
    private func parseRebaseApplyState(
        rebasePath: String,
        files: [GitFileStatus]
    ) throws -> RebaseState {
        let headNamePath = "\(rebasePath)/head-name"
        let ontoPath = "\(rebasePath)/onto"
        let nextPath = "\(rebasePath)/next"
        let lastPath = "\(rebasePath)/last"

        let branchName = try readFile(at: headNamePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "")

        let ontoCommit = try readFile(at: ontoPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let currentStep = Int(try readFile(at: nextPath).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let totalSteps = Int(try readFile(at: lastPath).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Extract conflicted files
        let conflicts = files
            .filter(\.hasConflict)
            .map(\.path)

        return RebaseState(
            branchName: branchName,
            ontoCommit: ontoCommit,
            currentStep: currentStep,
            totalSteps: totalSteps,
            conflicts: conflicts
        )
    }

    /// Helper to read file contents
    private func readFile(at path: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw GitStatusError.fileNotFound(path)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw GitStatusError.invalidEncoding(path)
        }
        return content
    }
}

/// Errors that can occur during status parsing
public enum GitStatusError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case invalidEncoding(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidEncoding(let path):
            return "Invalid encoding for file: \(path)"
        }
    }
}
