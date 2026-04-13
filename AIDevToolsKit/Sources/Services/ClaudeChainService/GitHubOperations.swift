import ClaudeChainSDK
import Foundation
import GitHubService

/// GitHub CLI and API operations
public struct GitHubOperations: GitHubOperationsProtocol {

    private let githubService: any GitHubPRServiceProtocol
    private let repositoryService: RepositoryService

    public init(githubService: any GitHubPRServiceProtocol, repositoryService: RepositoryService = RepositoryService()) {
        self.githubService = githubService
        self.repositoryService = repositoryService
    }

    // MARK: - GitHubOperationsProtocol

    /// Fetch file content from a specific branch via GitHub API
    ///
    /// - Parameter repo: GitHub repository in format "owner/repo"
    /// - Parameter branch: Branch name to fetch from
    /// - Parameter filePath: Path to file within repository
    /// - Returns: File content as string, or nil if file not found
    /// - Throws: GitHubAPIError if API call fails for reasons other than file not found
    public func getFileFromBranch(repo: String, branch: String, filePath: String) async throws -> String? {
        do {
            return try await githubService.fileContent(path: filePath, ref: branch)
        } catch {
            let desc = error.localizedDescription
            if desc.contains("404") || desc.lowercased().contains("not found") {
                return nil
            }
            throw error
        }
    }

    // MARK: - Instance methods (async, service-backed)

    /// Post a comment on a pull request (async version)
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prNumber: Pull request number to comment on
    /// - Parameter body: Comment text to post
    /// - Throws: GitHubAPIError if the operation fails
    public func postPRCommentAsync(repo: String, prNumber: Int, body: String) async throws {
        try await githubService.postIssueComment(prNumber: prNumber, body: body)
    }

    /// Delete a remote branch (async version)
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter branch: Branch name to delete
    /// - Throws: GitHubAPIError if the operation fails
    public func deleteBranchAsync(repo: String, branch: String) async throws {
        try await githubService.deleteBranch(branch: branch)
    }

    /// List remote branches, optionally filtered by prefix (async version)
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prefix: Optional prefix to filter branches (e.g., "claude-chain-")
    /// - Returns: Array of branch names
    /// - Throws: GitHubAPIError if the operation fails
    public func listBranchesAsync(repo: String, prefix: String? = nil) async throws -> [String] {
        let allBranches = try await githubService.listBranches(ttl: 0)
        if let prefix {
            return allBranches.filter { $0.hasPrefix(prefix) }
        }
        return allBranches
    }

    public func getCurrentRepository(workingDirectory: String) async throws -> String {
        do {
            return try await repositoryService.getCurrentRepository(workingDirectory: workingDirectory)
        } catch {
            throw GitHubAPIError("Unable to determine repository: \(error.localizedDescription)")
        }
    }

    // MARK: - Static utilities (no gh dependency)

    /// Extract project name from changed spec files.
    ///
    /// Looks for files matching pattern: claude-chain/{project}/spec.md
    ///
    /// - Parameter changedFiles: Array of file paths from compare_commits
    /// - Returns: Project name if exactly one spec.md was changed, nil otherwise
    /// - Throws: Error if multiple different spec.md files were changed
    public static func detectProjectFromDiff(changedFiles: [String]) throws -> String? {
        let specPattern = #"^claude-chain/([^/]+)/spec\.md$"#
        let regex = try NSRegularExpression(pattern: specPattern, options: [])
        var projects = Set<String>()

        for filePath in changedFiles {
            let range = NSRange(filePath.startIndex..<filePath.endIndex, in: filePath)
            if let match = regex.firstMatch(in: filePath, options: [], range: range),
               let projectRange = Range(match.range(at: 1), in: filePath) {
                let projectName = String(filePath[projectRange])
                projects.insert(projectName)
            }
        }

        if projects.count == 0 {
            return nil
        } else if projects.count == 1 {
            return projects.first
        } else {
            let sortedProjects = projects.sorted()
            throw NSError(domain: "ProjectDetectionError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Multiple projects modified in single push: \(sortedProjects). Push changes to one project at a time."
            ])
        }
    }

}
