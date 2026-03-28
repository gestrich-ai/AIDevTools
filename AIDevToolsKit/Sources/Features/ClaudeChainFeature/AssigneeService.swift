/**
 * Core service for assignee and capacity management.
 *
 * Follows Service Layer pattern (Fowler, PoEAA) - encapsulates business logic
 * for checking project capacity and providing assignee information.
 */

import ClaudeChainService
import ClaudeChainSDK

public class AssigneeService {
    /**
     * Core service for capacity checking and assignee management.
     *
     * This service checks whether a project has capacity for a new PR (based on
     * the configured maxOpenPRs limit) and provides the configured assignee (if any).
     */
    
    private let repo: String
    private let prService: PRService
    
    public init(repo: String, prService: PRService) {
        self.repo = repo
        self.prService = prService
    }
    
    public func checkCapacity(config: ProjectConfiguration, label: String, project: String) -> CapacityResult {
        /**
         * Check if project has capacity for a new PR.
         *
         * Capacity is determined by the project's maxOpenPRs setting (default: 1).
         *
         * Args:
         *     config: ProjectConfiguration domain model with optional assignee
         *     label: GitHub label to filter PRs
         *     project: Project name to match (used for filtering by branch name pattern)
         *
         * Returns:
         *     CapacityResult with capacity status, assignee, and open PRs list
         */
        let maxOpenPrs = config.getMaxOpenPRs()
        
        // Get all open PRs for this project (regardless of assignee)
        let openPrs = prService.getOpenPrsForProject(project: project, label: label)
        let openCount = openPrs.count
        
        // Build PR info list for display
        var prInfoList: [[String: Any]] = []
        for pr in openPrs {
            let prInfo: [String: Any] = [
                "pr_number": pr.number,
                "task_hash": pr.taskHash ?? "",
                "task_description": pr.taskDescription
            ]
            prInfoList.append(prInfo)
            print("PR #\(pr.number): project=\(project)")
        }
        
        let hasCapacity = openCount < maxOpenPrs
        
        print("Project \(project): \(openCount) open PR(s) (max: \(maxOpenPrs))")
        
        if hasCapacity {
            if !config.assignees.isEmpty {
                print("Capacity available - assignees: \(config.assignees.joined(separator: ", "))")
            } else {
                print("Capacity available (no assignee configured)")
            }
        } else {
            print("Project at capacity - skipping PR creation")
        }
        
        return CapacityResult(
            hasCapacity: hasCapacity,
            openPRs: prInfoList,
            projectName: project,
            maxOpenPRs: maxOpenPrs,
            assignees: config.assignees,
            reviewers: config.reviewers
        )
    }
}