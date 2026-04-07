import ClaudeChainFeature
import Foundation
import PipelineService
import Testing

@Suite("ChainRunOptions worktree")
struct ChainRunOptionsWorktreeTests {

    @Test("worktreeOptions defaults to nil")
    func worktreeOptionsDefaultsToNil() {
        let options = ChainRunOptions(
            baseBranch: "main",
            projectName: "my-project",
            repoPath: URL(fileURLWithPath: "/tmp/repo")
        )

        #expect(options.worktreeOptions == nil)
    }

    @Test("worktreeOptions stores provided value")
    func worktreeOptionsStoresValue() throws {
        let worktreeOptions = WorktreeOptions(
            branchName: "claude-chain-my-project-abc12345",
            destinationPath: "/tmp/worktrees/claude-chain-my-project-abc12345",
            repoPath: "/tmp/repo"
        )
        let options = ChainRunOptions(
            baseBranch: "main",
            projectName: "my-project",
            repoPath: URL(fileURLWithPath: "/tmp/repo"),
            worktreeOptions: worktreeOptions
        )

        let stored = try #require(options.worktreeOptions)
        #expect(stored.branchName == "claude-chain-my-project-abc12345")
        #expect(stored.destinationPath == "/tmp/worktrees/claude-chain-my-project-abc12345")
        #expect(stored.repoPath == "/tmp/repo")
    }
}
