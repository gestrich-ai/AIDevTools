/**
 * Service Layer utilities for artifact operations.
 *
 * Follows Service Layer pattern (Fowler, PoEAA) - provides a unified interface for
 * working with GitHub workflow artifacts that contain task metadata. These are utility
 * functions supporting the Service Layer rather than a full service class.
 */

import ClaudeChainService
import ClaudeChainSDK
import Foundation

public struct ProjectArtifact {
    /**
     * An artifact with its metadata
     */
    
    public let artifactId: Int
    public let artifactName: String
    public let workflowRunId: Int
    public var metadata: TaskMetadata?
    
    public init(artifactId: Int, artifactName: String, workflowRunId: Int, metadata: TaskMetadata? = nil) {
        self.artifactId = artifactId
        self.artifactName = artifactName
        self.workflowRunId = workflowRunId
        self.metadata = metadata
    }
    
    /**
     * Convenience accessor for task index
     */
    public var taskIndex: Int? {
        // TaskMetadata doesn't have taskIndex, parse from name
        return ArtifactService.parseTaskIndexFromName(artifactName: artifactName)
    }
}

// MARK: - Public API functions

public class ArtifactService {
    
    public static func findProjectArtifacts(
        repo: String,
        project: String,
        workflowFile: String,
        limit: Int = 50,
        downloadMetadata: Bool = false
    ) -> [ProjectArtifact] {
        /**
         * Find all artifacts for a project from a specific workflow.
         *
         * This is the primary API for getting project artifacts.
         *
         * Args:
         *     repo: GitHub repository (owner/name)
         *     project: Project name to filter artifacts
         *     workflowFile: Name of the workflow that creates PRs (from workflow's name: property)
         *     limit: Maximum number of workflow runs to check
         *     downloadMetadata: Whether to download full metadata JSON
         *
         * Returns:
         *     List of ProjectArtifact objects, optionally with metadata populated
         *
         * Algorithm:
         *     1. Query workflow runs for the specific workflow by name
         *     2. For each successful run, get its artifacts
         *     3. Filter artifacts by project name prefix
         *     4. Optionally download and parse metadata JSON
         */
        var resultArtifacts: [ProjectArtifact] = []
        var seenArtifactIds = Set<Int>()
        
        // Query workflow runs for the specific workflow
        // URL-encode the workflow name to handle spaces and special characters
        let workflowFileEncoded = workflowFile.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? workflowFile
        
        let runs: [[String: Any]]
        do {
            let apiResponse = try GitHubOperations.ghApiCall(endpoint: "/repos/\(repo)/actions/workflows/\(workflowFileEncoded)/runs?status=completed&per_page=\(limit)")
            runs = apiResponse["workflow_runs"] as? [[String: Any]] ?? []
        } catch {
            print("Warning: Failed to get workflow runs for '\(workflowFile)': \(error)")
            runs = []
        }
        
        print("Checking \(runs.count) workflow run(s) from '\(workflowFile)' for artifacts")
        
        // Process workflow runs and collect artifacts
        for run in runs {
            guard let conclusion = run["conclusion"] as? String,
                  conclusion == "success",
                  let runId = run["id"] as? Int else {
                continue
            }
            
            let artifacts = getArtifactsForRun(repo: repo, runId: runId)
            
            // Filter to project-specific artifacts
            let projectArtifacts = filterProjectArtifacts(artifacts: artifacts, project: project)
            
            for artifact in projectArtifacts {
                guard let artifactId = artifact["id"] as? Int,
                      let artifactName = artifact["name"] as? String else {
                    continue
                }
                
                // Skip if we've already seen this artifact
                if seenArtifactIds.contains(artifactId) {
                    continue
                }
                seenArtifactIds.insert(artifactId)
                
                // Create ProjectArtifact
                var projectArtifact = ProjectArtifact(
                    artifactId: artifactId,
                    artifactName: artifactName,
                    workflowRunId: runId,
                    metadata: nil
                )
                
                // Optionally download metadata
                if downloadMetadata {
                    if let metadataDict = GitHubOperations.downloadArtifactJson(repo: repo, artifactId: artifactId) {
                        do {
                            projectArtifact.metadata = TaskMetadata.fromDict(metadataDict)
                        } catch {
                            print("Warning: Failed to parse metadata for artifact \(artifactId): \(error)")
                        }
                    }
                }
                
                resultArtifacts.append(projectArtifact)
            }
        }
        
        print("Found \(resultArtifacts.count) artifact(s) for project '\(project)'")
        return resultArtifacts
    }
    
    public static func getArtifactMetadata(repo: String, artifactId: Int) -> TaskMetadata? {
        /**
         * Download and parse metadata from a specific artifact.
         *
         * Args:
         *     repo: GitHub repository (owner/name)
         *     artifactId: Artifact ID to download
         *
         * Returns:
         *     TaskMetadata object or nil if download fails
         */
        if let metadataDict = GitHubOperations.downloadArtifactJson(repo: repo, artifactId: artifactId) {
            do {
                return TaskMetadata.fromDict(metadataDict)
            } catch {
                print("Warning: Failed to parse metadata for artifact \(artifactId): \(error)")
            }
        }
        return nil
    }
    
    public static func findInProgressTasks(repo: String, project: String, workflowFile: String) -> Set<Int> {
        /**
         * Get task indices for all in-progress tasks (open PRs).
         *
         * This is a convenience wrapper around findProjectArtifacts.
         *
         * Args:
         *     repo: GitHub repository
         *     project: Project name
         *     workflowFile: Name of the workflow that creates PRs
         *
         * Returns:
         *     Set of task indices that are currently in progress
         */
        let artifacts = findProjectArtifacts(
            repo: repo,
            project: project,
            workflowFile: workflowFile,
            downloadMetadata: false  // Just need names
        )
        
        let taskIndices = Set(artifacts.compactMap { $0.taskIndex })
        return taskIndices
    }
    
    public static func getAssigneeAssignments(repo: String, project: String, workflowFile: String) -> [Int: String] {
        /**
         * Get mapping of PR numbers to assigned assignees.
         *
         * Args:
         *     repo: GitHub repository
         *     project: Project name
         *     workflowFile: Name of the workflow that creates PRs
         *
         * Returns:
         *     Dict mapping PR number -> assignee username
         */
        return [:]
    }
    
    // MARK: - Module utilities
    
    public static func parseTaskIndexFromName(artifactName: String) -> Int? {
        /**
         * Parse task index from artifact name.
         *
         * Expected format: task-metadata-{project}-{index}.json
         *
         * Args:
         *     artifactName: Artifact name
         *
         * Returns:
         *     Task index or nil if parsing fails
         */
        // Pattern: task-metadata-{project}-{index}.json
        // Example: task-metadata-myproject-1.json
        // Note: Project names can contain dashes, so we use .+ to match the entire project name
        // and capture the last number before .json
        let pattern = #"task-metadata-.+-(\d+)\.json"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: artifactName.utf16.count)
            
            if let match = regex.firstMatch(in: artifactName, options: [], range: range) {
                let numberRange = Range(match.range(at: 1), in: artifactName)!
                let numberString = String(artifactName[numberRange])
                return Int(numberString)
            }
        } catch {
            print("Error parsing artifact name: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Private helper functions
    
    private static func getWorkflowRunsForBranch(repo: String, branch: String, limit: Int = 10) -> [[String: Any]] {
        /**
         * Get workflow runs for a branch
         *
         * Args:
         *     repo: GitHub repository (owner/name)
         *     branch: Branch name
         *     limit: Maximum number of runs to fetch
         *
         * Returns:
         *     List of workflow run dictionaries
         *
         * Throws:
         *     GitHubAPIError: If API call fails
         */
        do {
            let apiResponse = try GitHubOperations.ghApiCall(
                endpoint: "/repos/\(repo)/actions/runs?branch=\(branch)&status=completed&per_page=\(limit)"
            )
            return apiResponse["workflow_runs"] as? [[String: Any]] ?? []
        } catch {
            print("Warning: Failed to get workflow runs for branch \(branch): \(error)")
            return []
        }
    }
    
    private static func getArtifactsForRun(repo: String, runId: Int) -> [[String: Any]] {
        /**
         * Get artifacts from a workflow run
         *
         * Args:
         *     repo: GitHub repository (owner/name)
         *     runId: Workflow run ID
         *
         * Returns:
         *     List of artifact dictionaries
         *
         * Throws:
         *     GitHubAPIError: If API call fails
         */
        do {
            let artifactsData = try GitHubOperations.ghApiCall(endpoint: "/repos/\(repo)/actions/runs/\(runId)/artifacts")
            return artifactsData["artifacts"] as? [[String: Any]] ?? []
        } catch {
            print("Warning: Failed to get artifacts for run \(runId): \(error)")
            return []
        }
    }
    
    private static func filterProjectArtifacts(artifacts: [[String: Any]], project: String) -> [[String: Any]] {
        /**
         * Filter artifacts by project name pattern
         *
         * Args:
         *     artifacts: List of artifact dictionaries
         *     project: Project name to filter by
         *
         * Returns:
         *     List of artifacts matching the project
         */
        return artifacts.filter { artifact in
            guard let name = artifact["name"] as? String else {
                return false
            }
            return name.hasPrefix("task-metadata-\(project)-")
        }
    }
}