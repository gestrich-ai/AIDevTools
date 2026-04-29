import Foundation
import Testing
@testable import SkillScannerSDK

@Suite("SkillScanner")
struct SkillScannerTests {
    private func makeTempRepo(skillFiles: [String], directory: String = ".claude/skills") throws -> URL {
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir.appendingPathComponent(directory)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        for file in skillFiles {
            let filePath = skillsDir.appendingPathComponent(file)
            try "# Skill content".write(to: filePath, atomically: true, encoding: .utf8)
        }
        return repoDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("finds markdown files in skills directory") func scanFindsMarkdownFiles() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["commit.md", "review.md"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 2)
        #expect(skills[0].name == "commit")
        #expect(skills[1].name == "review")
    }

    @Test("ignores non-markdown files") func scanIgnoresNonMarkdownFiles() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["skill.md", "readme.txt", "data.json"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "skill")
    }

    @Test("returns empty when no skills directory exists") func scanReturnsEmptyWhenNoSkillsDirectory() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.isEmpty)
    }

    @Test("returns skills sorted alphabetically by name") func scanReturnsSortedByName() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["zebra.md", "alpha.md", "middle.md"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.map(\.name) == ["alpha", "middle", "zebra"])
    }

    @Test("finds skills packaged as subdirectories") func scanFindsSubdirectories() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
        let subdir = skillsDir.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "# Skill".write(to: subdir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "my-skill")
        // standardizedFileURL resolves symlinks (handles /var→/private/var on macOS).
        // Strip trailing slash before comparing — Linux contentsOfDirectory adds it for directories.
        let lhs = skills[0].path.standardizedFileURL.path
        let rhs = subdir.standardizedFileURL.path
        #expect((lhs.hasSuffix("/") ? String(lhs.dropLast()) : lhs) == (rhs.hasSuffix("/") ? String(rhs.dropLast()) : rhs))
    }

    @Test("includes reference files found alongside SKILL.md in a subdirectory") func scanFindsReferenceFilesInSubdirectory() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
        let subdir = skillsDir.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "# Main skill".write(to: subdir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "# Guide".write(to: subdir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)
        try "# Examples".write(to: subdir.appendingPathComponent("examples.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].referenceFiles.count == 2)
        #expect(skills[0].referenceFiles[0].name == "examples")
        #expect(skills[0].referenceFiles[1].name == "guide")
    }

    @Test("finds skills in .agents/skills directory") func scanFindsSkillsInAgentsDirectory() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["deploy.md"], directory: ".agents/skills")
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "deploy")
    }

    @Test(".agents/skills takes precedence over .claude/skills for same-named skills") func agentsSkillsPreferredOverClaudeSkills() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let agentsDir = repoDir.appendingPathComponent(".agents/skills")
        let claudeDir = repoDir.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try "# Agents version".write(to: agentsDir.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        try "# Claude version".write(to: claudeDir.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        try "# Claude only".write(to: claudeDir.appendingPathComponent("claude-only.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 2)
        #expect(skills.map(\.name) == ["claude-only", "shared"])
        let shared = skills.first(where: { $0.name == "shared" })!
        #expect(shared.path.path.contains(".agents/skills"))
    }

    @Test("standalone markdown file has no reference files") func standaloneMarkdownHasNoReferenceFiles() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["commit.md"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].referenceFiles.isEmpty)
    }

    // MARK: - Commands Directory Scanning

    @Test("finds commands in .claude/commands directory") func scanFindsCommandsInClaudeCommandsDirectory() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["deploy.md"], directory: ".claude/commands")
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "deploy")
    }

    @Test("finds commands in .agents/commands directory") func scanFindsCommandsInAgentsCommandsDirectory() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["deploy.md"], directory: ".agents/commands")
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "deploy")
    }

    @Test("names nested commands using subdirectory path prefix") func scanFindsNestedCommandsWithPathNames() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let commandsDir = repoDir.appendingPathComponent(".claude/commands")
        let subdir = commandsDir.appendingPathComponent("deploy")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "# Deploy staging".write(to: subdir.appendingPathComponent("staging.md"), atomically: true, encoding: .utf8)
        try "# Deploy prod".write(to: subdir.appendingPathComponent("production.md"), atomically: true, encoding: .utf8)
        try "# Top-level".write(to: commandsDir.appendingPathComponent("commit.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 3)
        #expect(skills.map(\.name) == ["commit", "deploy/production", "deploy/staging"])
    }

    @Test("skills directory takes precedence over commands directory for same-named entries") func skillsOverrideCommandsWithSameName() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir.appendingPathComponent(".claude/skills")
        let commandsDir = repoDir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        try "# Skill version".write(to: skillsDir.appendingPathComponent("deploy.md"), atomically: true, encoding: .utf8)
        try "# Command version".write(to: commandsDir.appendingPathComponent("deploy.md"), atomically: true, encoding: .utf8)
        try "# Command only".write(to: commandsDir.appendingPathComponent("commit.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 2)
        #expect(skills.map(\.name) == ["commit", "deploy"])
        let deploy = skills.first(where: { $0.name == "deploy" })!
        #expect(deploy.path.path.contains(".claude/skills"))
    }

    @Test("discovers commands in global commands directory") func globalCommandsAreDiscovered() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let globalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: globalDir, withIntermediateDirectories: true)
        try "# Global command".write(to: globalDir.appendingPathComponent("global-cmd.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir); cleanup(globalDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: globalDir)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "global-cmd")
    }

    @Test("local commands take precedence over global commands with same name") func localCommandsOverrideGlobalCommands() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let globalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let localCommandsDir = repoDir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: localCommandsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: globalDir, withIntermediateDirectories: true)
        try "# Local version".write(to: localCommandsDir.appendingPathComponent("deploy.md"), atomically: true, encoding: .utf8)
        try "# Global version".write(to: globalDir.appendingPathComponent("deploy.md"), atomically: true, encoding: .utf8)
        try "# Global only".write(to: globalDir.appendingPathComponent("global-only.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir); cleanup(globalDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: globalDir)

        // Assert
        #expect(skills.count == 2)
        #expect(skills.map(\.name) == ["deploy", "global-only"])
        let deploy = skills.first(where: { $0.name == "deploy" })!
        #expect(deploy.path.path.contains(".claude/commands"))
    }

    @Test(".agents/commands takes precedence over .claude/commands for same-named commands") func agentsCommandsPreferredOverClaudeCommands() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let agentsDir = repoDir.appendingPathComponent(".agents/commands")
        let claudeDir = repoDir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try "# Agents version".write(to: agentsDir.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        try "# Claude version".write(to: claudeDir.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        try "# Claude only".write(to: claudeDir.appendingPathComponent("claude-only.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 2)
        #expect(skills.map(\.name) == ["claude-only", "shared"])
        let shared = skills.first(where: { $0.name == "shared" })!
        #expect(shared.path.path.contains(".agents/commands"))
    }

    @Test("ignores non-markdown files in commands directory") func commandsIgnoresNonMarkdownFiles() throws {
        // Arrange
        let repoDir = try makeTempRepo(
            skillFiles: ["deploy.md", "readme.txt", "config.json"],
            directory: ".claude/commands"
        )
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir, globalCommandsDirectory: nil)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "deploy")
    }
}
