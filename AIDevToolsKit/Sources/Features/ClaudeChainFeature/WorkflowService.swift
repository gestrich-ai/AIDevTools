import ClaudeChainService
import Foundation
import GitHubService
import Logging

public struct WorkflowService {

    private let githubService: any GitHubPRServiceProtocol
    private let logger = Logger(label: "WorkflowService")

    public init(githubService: any GitHubPRServiceProtocol) {
        self.githubService = githubService
    }

    public func triggerClaudeChainWorkflow(projectName: String, baseBranch: String, checkoutRef: String) throws {
        var triggerError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await githubService.triggerWorkflowDispatch(
                    workflowId: "claudechain.yml",
                    ref: checkoutRef,
                    inputs: [
                        ClaudeChainConstants.workflowProjectNameKey: projectName,
                        ClaudeChainConstants.workflowBaseBranchKey: baseBranch,
                        "checkout_ref": checkoutRef,
                    ]
                )
            } catch let e {
                triggerError = e
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = triggerError {
            throw GitHubAPIError("Failed to trigger workflow for project '\(projectName)': \(error)")
        }
    }

    public func batchTriggerClaudeChainWorkflows(projects: [String], baseBranch: String, checkoutRef: String) -> ([String], [String]) {
        var successful: [String] = []
        var failed: [String] = []

        for project in projects {
            do {
                try triggerClaudeChainWorkflow(projectName: project, baseBranch: baseBranch, checkoutRef: checkoutRef)
                successful.append(project)
                logger.info("triggered workflow for project: \(project)")
            } catch {
                failed.append(project)
                logger.error("failed to trigger workflow for project '\(project)': \(error)")
            }
        }

        return (successful, failed)
    }
}
