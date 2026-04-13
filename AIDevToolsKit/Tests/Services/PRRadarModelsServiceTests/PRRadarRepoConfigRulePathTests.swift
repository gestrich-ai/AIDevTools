import Foundation
import RepositorySDK
import Testing
@testable import PRRadarConfigService

@Suite("PRRadarRepoConfig rule path")
struct PRRadarRepoConfigRulePathTests {

    // MARK: - defaultRulePath

    @Test("returns the rule path marked as default") func defaultRulePathReturnsMarkedDefault() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [
                RulePath(name: "shared", path: "/shared/rules", isDefault: false),
                RulePath(name: "local", path: "local-rules", isDefault: true),
            ],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.defaultRulePath

        // Assert
        #expect(result?.name == "local")
    }

    @Test("falls back to first rule path when none marked as default") func defaultRulePathFallsBackToFirst() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [
                RulePath(name: "first", path: "first-rules", isDefault: false),
                RulePath(name: "second", path: "second-rules", isDefault: false),
            ],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.defaultRulePath

        // Assert
        #expect(result?.name == "first")
    }

    @Test("returns nil when rule paths list is empty") func defaultRulePathReturnsNilWhenEmpty() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.defaultRulePath

        // Assert
        #expect(result == nil)
    }

    // MARK: - resolvedDefaultRulesDir

    @Test("returns absolute path unchanged") func resolvedDefaultRulesDirWithAbsolutePath() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "shared", path: "/Users/bill/shared-rules", isDefault: true)],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        #expect(result == "/Users/bill/shared-rules")
    }

    @Test("resolves relative path against repo path") func resolvedDefaultRulesDirWithRelativePath() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "local", path: "code-review-rules", isDefault: true)],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        #expect(result == "/tmp/repo/code-review-rules")
    }

    @Test("expands tilde to home directory") func resolvedDefaultRulesDirWithTildePath() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "home", path: "~/shared-rules", isDefault: true)],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(result == "\(home)/shared-rules")
    }

    @Test("returns empty string when no rule paths configured") func resolvedDefaultRulesDirReturnsEmptyWhenNoRulePaths() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        #expect(result == "")
    }

    // MARK: - resolvedRulesDir(named:)

    @Test("returns resolved path for named rule path") func resolvedRulesDirNamedFindsMatchingPath() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [
                RulePath(name: "shared", path: "/shared/rules", isDefault: true),
                RulePath(name: "local", path: "local-rules", isDefault: false),
            ],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.resolvedRulesDir(named: "local")

        // Assert
        #expect(result == "/tmp/repo/local-rules")
    }

    @Test("returns nil for unknown rule path name") func resolvedRulesDirNamedReturnsNilForUnknownName() {
        // Arrange
        let config = PRRadarRepoConfig(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "shared", path: "/shared/rules", isDefault: true)],
            githubAccount: "test",
            defaultBaseBranch: "main"
        )

        // Act
        let result = config.resolvedRulesDir(named: "nonexistent")

        // Assert
        #expect(result == nil)
    }
}
