/**
 * Core service for PR operations and branch naming utilities.
 *
 * Follows Service Layer pattern (Fowler, PoEAA) - provides a unified interface
 * for branch naming and PR fetching, eliminating duplication across the codebase.
 * Encapsulates business logic for PR-related operations.
 */

import ClaudeChainService
import ClaudeChainSDK
import Foundation

public class PRService {
    /**
     * Core service for PR operations and branch naming utilities.
     *
     * Coordinates PR fetching and branch naming operations by orchestrating
     * GitHub API interactions. Implements business logic for ClaudeChain's
     * PR management workflows.
     */
    
    private let repo: String
    
    /**
     * Initialize PR service
     *
     * Args:
     *     repo: GitHub repository (owner/name)
     */
    public init(repo: String) {
        self.repo = repo
    }
    
    // MARK: - Public API methods
    
    public func getProjectPrs(projectName: String, state: String = "all", label: String = "claudechain") -> [GitHubPullRequest] {
        /**
         * Fetch all PRs for a project by branch prefix.
         *
         * This is the primary API for getting PRs associated with a ClaudeChain project.
         * It filters PRs by matching the branch name pattern.
         *
         * Args:
         *     projectName: Project name (e.g., "my-refactor")
         *     state: PR state filter - "open", "closed", "merged", or "all"
         *     label: GitHub label to filter PRs (default: "claudechain")
         *
         * Returns:
         *     List of GitHubPullRequest domain models filtered by project
         *
         * Throws:
         *     GitHubAPIError: If the GitHub API call fails
         *
         * Examples:
         *     let service = PRService("owner/repo")
         *     let prs = service.getProjectPrs(projectName: "my-refactor", state: "open")
         *     prs.count  // 3
         *     prs[0].headRefName  // "claude-chain-my-refactor-1"
         */
        print("Fetching PRs for project '\(projectName)' with state='\(state)' and label='\(label)'")
        
        // Fetch PRs with the label using infrastructure layer
        do {
            let allPrs = try GitHubOperations.listPullRequests(
                repo: repo,
                state: state,
                label: label,
                limit: 100
            )
            
            // Filter to only PRs whose branch names match the exact project name.
            // We parse each branch name to extract the project name precisely,
            // avoiding false matches when one project name is a prefix of another
            // (e.g., "auth" should not match "auth-api" branches).
            let projectPrs = allPrs.filter { pr in
                guard let headRefName = pr.headRefName,
                      let parsed = BranchInfo.fromBranchName(headRefName) else {
                    return false
                }
                return parsed.projectName == projectName
            }
            
            print("Found \(projectPrs.count) PR(s) for project '\(projectName)' (out of \(allPrs.count) total)")
            return projectPrs
        } catch {
            print("Warning: Failed to list PRs: \(error)")
            return []
        }
    }
    
    public func getOpenPrsForProject(project: String, label: String = "claudechain") -> [GitHubPullRequest] {
        /**
         * Fetch open PRs for a project.
         *
         * Convenience wrapper for getProjectPrs() with state="open".
         *
         * Args:
         *     project: Project name (e.g., "my-refactor")
         *     label: GitHub label to filter PRs (default: "claudechain")
         *
         * Returns:
         *     List of open GitHubPullRequest domain models for the project
         *
         * Examples:
         *     let service = PRService("owner/repo")
         *     let openPrs = service.getOpenPrsForProject("my-refactor")
         *     openPrs.allSatisfy { $0.isOpen() }  // true
         */
        return getProjectPrs(projectName: project, state: "open", label: label)
    }
    
    public func getMergedPrsForProject(project: String, label: String = "claudechain", daysBack: Int = Constants.defaultStatsDaysBack) -> [GitHubPullRequest] {
        /**
         * Fetch merged PRs for a project within a time window.
         *
         * Convenience wrapper for getProjectPrs() with state="merged",
         * filtered to only include PRs merged within the specified days.
         *
         * Args:
         *     project: Project name (e.g., "my-refactor")
         *     label: GitHub label to filter PRs (default: "claudechain")
         *     daysBack: Only include PRs merged within this many days (default: 30)
         *
         * Returns:
         *     List of merged GitHubPullRequest domain models for the project
         *
         * Examples:
         *     let service = PRService("owner/repo")
         *     let mergedPrs = service.getMergedPrsForProject("my-refactor", daysBack: 7)
         *     mergedPrs.allSatisfy { $0.isMerged() }  // true
         */
        let allMerged = getProjectPrs(projectName: project, state: "merged", label: label)
        
        // Filter by merge date
        let cutoff = Date().addingTimeInterval(-Double(daysBack * 24 * 60 * 60))
        let recentMerged = allMerged.filter { pr in
            guard let mergedAt = pr.mergedAt else { return false }
            return mergedAt >= cutoff
        }
        
        return recentMerged
    }
    
    public func getAllPrs(label: String = "claudechain", state: String = "all", limit: Int = 500) -> [GitHubPullRequest] {
        /**
         * Fetch all PRs with the specified label.
         *
         * Used for statistics and project discovery across all ClaudeChain PRs.
         *
         * Args:
         *     label: GitHub label to filter PRs (default: "claudechain")
         *     state: PR state filter - "open", "closed", "merged", or "all"
         *     limit: Max results (default: 500)
         *
         * Returns:
         *     List of GitHubPullRequest domain models with the label
         *
         * Examples:
         *     let service = PRService("owner/repo")
         *     let allPrs = service.getAllPrs()
         *     allPrs.count  // 150
         */
        do {
            return try GitHubOperations.listPullRequests(
                repo: repo,
                state: state,
                label: label,
                limit: limit
            )
        } catch {
            print("Warning: Failed to list all PRs: \(error)")
            return []
        }
    }
    
    public func getUniqueProjects(label: String = "claudechain") -> [String: String] {
        /**
         * Extract unique project names and their base branches from labeled PRs.
         *
         * Used by statistics service for multi-project discovery. Returns a mapping
         * of project names to their base branches, allowing statistics to query
         * spec files from the correct branch for each project.
         *
         * Args:
         *     label: GitHub label to filter PRs (default: "claudechain")
         *
         * Returns:
         *     Dict mapping project name to base branch (branch PR was merged into)
         *
         * Examples:
         *     let service = PRService("owner/repo")
         *     let projects = service.getUniqueProjects()
         *     // projects: ["my-refactor": "main", "swift-migration": "develop", "api-cleanup": "main"]
         */
        let allPrs = getAllPrs(label: label)
        
        // Sort by created_at descending so we process newest PRs first
        let allPrsSorted = allPrs.sorted { $0.createdAt > $1.createdAt }
        
        var projects: [String: String] = [:]
        for pr in allPrsSorted {
            guard let headRefName = pr.headRefName,
                  let baseRefName = pr.baseRefName,
                  let parsed = PRService.parseBranchName(branch: headRefName) else {
                continue
            }
            
            let projectName = parsed.projectName
            // Keep the newest PR's base branch for each project.
            // Old PRs may have targeted different branches before the project
            // was moved to its current base branch.
            if projects[projectName] == nil {
                projects[projectName] = baseRefName
            }
        }
        
        return projects
    }
    
    // MARK: - Static utility methods
    
    public static func formatBranchName(projectName: String, taskHash: String) -> String {
        /**
         * Format branch name using the standard ClaudeChain format (hash-based).
         *
         * This method now uses hash-based identification for stable task tracking.
         * The signature has been updated from index-based to hash-based.
         *
         * Args:
         *     projectName: Project name (e.g., "my-refactor")
         *     taskHash: 8-character task hash from generateTaskHash()
         *
         * Returns:
         *     Formatted branch name (e.g., "claude-chain-my-refactor-a3f2b891")
         *
         * Examples:
         *     PRService.formatBranchName("my-refactor", "a3f2b891")  // "claude-chain-my-refactor-a3f2b891"
         *     PRService.formatBranchName("swift-migration", "f7c4d3e2")  // "claude-chain-swift-migration-f7c4d3e2"
         */
        return formatBranchNameWithHash(projectName: projectName, taskHash: taskHash)
    }
    
    public static func formatBranchNameWithHash(projectName: String, taskHash: String) -> String {
        /**
         * Format branch name using hash-based ClaudeChain format.
         *
         * This is the new format that provides stable task identification
         * regardless of task position in spec.md.
         *
         * Args:
         *     projectName: Project name (e.g., "my-refactor")
         *     taskHash: 8-character task hash from generateTaskHash()
         *
         * Returns:
         *     Formatted branch name (e.g., "claude-chain-my-refactor-a3f2b891")
         *
         * Examples:
         *     PRService.formatBranchNameWithHash("my-refactor", "a3f2b891")  // "claude-chain-my-refactor-a3f2b891"
         *     PRService.formatBranchNameWithHash("auth-refactor", "f7c4d3e2")  // "claude-chain-auth-refactor-f7c4d3e2"
         */
        return "claude-chain-\(projectName)-\(taskHash)"
    }
    
    public static func parseBranchName(branch: String) -> BranchInfo? {
        /**
         * Parse branch name for hash-based format.
         *
         * Expected format: claude-chain-{project_name}-{hash}
         *
         * Args:
         *     branch: Branch name to parse
         *
         * Returns:
         *     BranchInfo instance if branch matches pattern, nil otherwise
         *
         * Examples:
         *     let info = PRService.parseBranchName("claude-chain-my-refactor-a3f2b891")
         *     info.projectName  // "my-refactor"
         *     info.taskHash  // "a3f2b891"
         *     PRService.parseBranchName("invalid-branch")  // nil
         */
        return BranchInfo.fromBranchName(branch)
    }
}