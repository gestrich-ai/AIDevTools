import GitSDK
import PipelineService
import Testing

@Suite("WorktreeOptions")
struct WorktreeOptionsTests {

    @Test("stores branchName, destinationPath, and repoPath")
    func propertiesRoundTrip() {
        let options = WorktreeOptions(
            branchName: "feature-branch",
            destinationPath: "/tmp/worktrees/feature-branch",
            repoPath: "/path/to/repo"
        )

        #expect(options.branchName == "feature-branch")
        #expect(options.destinationPath == "/tmp/worktrees/feature-branch")
        #expect(options.repoPath == "/path/to/repo")
    }
}

@Suite("WorktreeNode")
struct WorktreeNodeTests {

    private func makeNode() -> WorktreeNode {
        let options = WorktreeOptions(
            branchName: "plan-abc123",
            destinationPath: "/tmp/worktrees/plan-abc123",
            repoPath: "/tmp/repo"
        )
        return WorktreeNode(options: options, gitClient: GitClient())
    }

    @Test("id is worktree-node")
    func nodeId() {
        let node = makeNode()
        #expect(node.id == "worktree-node")
    }

    @Test("displayName is Creating worktree")
    func nodeDisplayName() {
        let node = makeNode()
        #expect(node.displayName == "Creating worktree")
    }

    @Test("worktreePathKey name is WorktreeNode.worktreePath")
    func worktreePathKeyIdentifier() {
        #expect(WorktreeNode.worktreePathKey.name == "WorktreeNode.worktreePath")
    }
}
