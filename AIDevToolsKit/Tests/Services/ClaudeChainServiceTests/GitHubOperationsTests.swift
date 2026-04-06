import ClaudeChainService
import Foundation
import Testing

@Suite("GitHubOperations.detectProjectFromDiff")
struct GitHubOperationsDetectProjectTests {

    @Test("detects single project from spec.md path")
    func singleProject() throws {
        let changedFiles = [
            "claude-chain/my-project/spec.md",
            "README.md",
        ]
        let project = try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles)
        #expect(project == "my-project")
    }

    @Test("returns nil when no spec.md changed")
    func noSpecFiles() throws {
        let changedFiles = [
            "src/main.swift",
            "docs/README.md",
            "package.json",
        ]
        let project = try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles)
        #expect(project == nil)
    }

    @Test("throws when multiple projects changed")
    func multipleProjectsThrows() {
        let changedFiles = [
            "claude-chain/database-migration/spec.md",
            "claude-chain/user-auth/spec.md",
        ]
        #expect(throws: Error.self) {
            try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles)
        }
    }

    @Test("ignores non-spec.md files inside project directory")
    func ignoresNonSpecFiles() throws {
        let changedFiles = [
            "claude-chain/my-project/configuration.yml",
            "claude-chain/my-project/pre-action.sh",
            "claude-chain/my-project/spec.md",
        ]
        let project = try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles)
        #expect(project == "my-project")
    }
}
