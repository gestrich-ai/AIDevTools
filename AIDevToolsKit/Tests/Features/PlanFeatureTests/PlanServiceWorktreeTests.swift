import AIOutputSDK
import Foundation
import PipelineService
import PlanFeature
import Testing

@Suite("PlanService.buildExecutePipeline worktree")
struct PlanServiceWorktreeTests {

    private func makeTempPlanFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("plan.md")
        try """
        ## - [ ] Implement feature
        ## - [ ] Add tests
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("with worktreeOptions set, first node is worktree-node")
    func buildWithWorktreeOptionsPrependsWorktreeNode() async throws {
        let planURL = try makeTempPlanFile()
        defer { try? FileManager.default.removeItem(at: planURL.deletingLastPathComponent()) }

        let worktreeOptions = WorktreeOptions(
            branchName: "plan-abc123",
            destinationPath: "/tmp/worktrees/plan-abc123",
            repoPath: "/tmp/repo"
        )
        let service = PlanService(client: StubAIClient()) { _ in planURL.deletingLastPathComponent() }
        let options = PlanService.ExecuteOptions(planPath: planURL, worktreeOptions: worktreeOptions)

        let blueprint = try await service.buildExecutePipeline(options: options)

        #expect(blueprint.nodes.first?.id == "worktree-node")
    }

    @Test("without worktreeOptions, first node is task-source")
    func buildWithoutWorktreeOptionsUsesTaskSourceAsFirstNode() async throws {
        let planURL = try makeTempPlanFile()
        defer { try? FileManager.default.removeItem(at: planURL.deletingLastPathComponent()) }

        let service = PlanService(client: StubAIClient()) { _ in planURL.deletingLastPathComponent() }
        let options = PlanService.ExecuteOptions(planPath: planURL)

        let blueprint = try await service.buildExecutePipeline(options: options)

        #expect(blueprint.nodes.first?.id == "task-source")
    }
}

private struct StubAIClient: AIClient {
    let displayName = "Stub"
    let name = "stub"

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        AIClientResult(exitCode: 0, stderr: "", stdout: "")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        throw StubError.notImplemented
    }

    private enum StubError: Error {
        case notImplemented
    }
}
