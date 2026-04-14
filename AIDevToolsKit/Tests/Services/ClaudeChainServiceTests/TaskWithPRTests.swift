import Foundation
import GitHubService
import Testing

@testable import ClaudeChainService

@Suite("TaskWithPR")
struct TaskWithPRTests {

    // MARK: - TaskStatus

    @Test("pending has raw value 'pending'")
    func pendingStatusValue() {
        #expect(TaskStatus.pending.rawValue == "pending")
    }

    @Test("inProgress has raw value 'in_progress'")
    func inProgressStatusValue() {
        #expect(TaskStatus.inProgress.rawValue == "in_progress")
    }

    @Test("completed has raw value 'completed'")
    func completedStatusValue() {
        #expect(TaskStatus.completed.rawValue == "completed")
    }

    @Test("all status raw values are distinct")
    func allStatusesAreDistinct() {
        let statuses = [TaskStatus.pending, TaskStatus.inProgress, TaskStatus.completed]
        #expect(statuses.count == 3)
        let values = Set(statuses.map { $0.rawValue })
        #expect(values.count == 3)
    }

    // MARK: - TaskWithPR

    @Test("stores all fields on creation")
    func taskWithPRCreation() {
        let samplePR = makeSamplePR()
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: samplePR
        )

        #expect(task.taskHash == "a3f2b891")
        #expect(task.description == "Add user authentication")
        #expect(task.status == .inProgress)
        #expect(task.pr == samplePR)
    }

    @Test("pr is nil for a pending task without a PR")
    func taskWithoutPR() {
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )

        #expect(task.taskHash == "c5d4e3f2")
        #expect(task.description == "Add logging")
        #expect(task.status == .pending)
        #expect(task.pr == nil)
    }

    @Test("hasPR returns true when PR is assigned")
    func hasPRReturnsTrueWhenPRExists() {
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: makeSamplePR()
        )

        #expect(task.hasPR)
    }

    @Test("hasPR returns false when no PR is assigned")
    func hasPRReturnsFalseWhenNoPR() {
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )

        #expect(!task.hasPR)
    }

    @Test("prNumber returns number when PR is assigned")
    func prNumberReturnsNumberWhenPRExists() {
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: makeSamplePR()
        )

        #expect(task.prNumber == 42)
    }

    @Test("prNumber returns nil when no PR is assigned")
    func prNumberReturnsNilWhenNoPR() {
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )

        #expect(task.prNumber == nil)
    }

    @Test("prState returns open for an open PR")
    func prStateReturnsStateWhenPRExists() {
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: makeSamplePR()
        )

        #expect(task.prState == PRState.open)
    }

    @Test("prState returns merged for a merged PR")
    func prStateReturnsMergedForMergedPR() {
        let task = TaskWithPR(
            taskHash: "b4c3d2e1",
            description: "Add input validation",
            status: .completed,
            pr: makeMergedPR()
        )

        #expect(task.prState == PRState.merged)
    }

    @Test("prState returns nil when no PR is assigned")
    func prStateReturnsNilWhenNoPR() {
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )

        #expect(task.prState == nil)
    }

    @Test("completed task with merged PR has all expected properties")
    func completedTaskWithMergedPR() {
        let task = TaskWithPR(
            taskHash: "b4c3d2e1",
            description: "Add input validation",
            status: .completed,
            pr: makeMergedPR()
        )

        #expect(task.status == .completed)
        #expect(task.hasPR)
        #expect(task.prNumber == 41)
        #expect(task.prState == PRState.merged)
    }

    // MARK: - ProjectStats

    @Test("ProjectStats initializes with empty tasks list")
    func projectStatsInitializesEmptyTasksList() {
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")

        #expect(stats.tasks == [] as [TaskWithPR])
    }

    @Test("ProjectStats initializes with empty orphanedPRs list")
    func projectStatsInitializesEmptyOrphanedPRsList() {
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")

        #expect(stats.orphanedPRs == [] as [ClaudeChainService.GitHubPullRequest])
    }

    @Test("ProjectStats allows appending tasks")
    func projectStatsCanAddTasks() {
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add feature",
            status: .inProgress,
            pr: makeSamplePR()
        )

        stats.tasks.append(task)

        #expect(stats.tasks.count == 1)
        #expect(stats.tasks[0].taskHash == "a3f2b891")
    }

    @Test("ProjectStats allows appending orphaned PRs")
    func projectStatsCanAddOrphanedPRs() {
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")

        stats.orphanedPRs.append(makeSamplePR())

        #expect(stats.orphanedPRs.count == 1)
        #expect(stats.orphanedPRs[0].number == 42)
    }

    @Test("tasks and orphanedPRs are independent lists")
    func projectStatsTasksAndOrphanedPRsIndependent() {
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add feature",
            status: .pending,
            pr: nil
        )

        stats.tasks.append(task)
        stats.orphanedPRs.append(makeSamplePR())

        #expect(stats.tasks.count == 1)
        #expect(stats.orphanedPRs.count == 1)
        #expect(stats.tasks[0].pr == nil)
        #expect(stats.orphanedPRs[0].number == 42)
    }

    // MARK: - Helpers

    private func makeSamplePR() -> ClaudeChainService.GitHubPullRequest {
        ClaudeChainService.GitHubPullRequest(
            number: 42,
            title: "ClaudeChain: Add user authentication",
            state: "open",
            createdAt: Date(timeIntervalSince1970: 1672574400),
            mergedAt: nil,
            assignees: [GitHubUser(login: "alice")],
            labels: ["claudechain"],
            headRefName: "claude-chain-my-project-a3f2b891"
        )
    }

    private func makeMergedPR() -> ClaudeChainService.GitHubPullRequest {
        ClaudeChainService.GitHubPullRequest(
            number: 41,
            title: "ClaudeChain: Add input validation",
            state: "merged",
            createdAt: Date(timeIntervalSince1970: 1672567200),
            mergedAt: Date(timeIntervalSince1970: 1672675200),
            assignees: [GitHubUser(login: "bob")],
            labels: ["claudechain"],
            headRefName: "claude-chain-my-project-b4c3d2e1"
        )
    }
}
