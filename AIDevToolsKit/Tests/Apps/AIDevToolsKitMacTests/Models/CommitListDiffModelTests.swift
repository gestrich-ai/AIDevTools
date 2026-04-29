import Foundation
import GitSDK
import LocalDiffService
import Testing
@testable import AIDevToolsKitMac

@MainActor
@Suite("CommitListDiffModel")
struct CommitListDiffModelTests {
    private let gitClient = GitClient()
    private let diffService = LocalDiffService()

    @Test("All plan commits selects only commits whose subjects match completed phase descriptions")
    func selectPlanCommitsMatchesCompletedPhaseMessages() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("phase one\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Complete Phase 1: Setup")
        let phaseOneHash = try await gitClient.getHeadHash(workingDirectory: repo)

        try write("phase one\nphase two\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Complete Phase 2: Validation")
        let phaseTwoHash = try await gitClient.getHeadHash(workingDirectory: repo)

        try write("phase one\nphase two\nother\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Refactor unrelated code")

        let model = CommitListDiffModel(
            diffService: diffService,
            workingDirectoryMonitor: GitWorkingDirectoryMonitor(),
            planPhaseDescriptions: ["Setup", "Validation"],
            repoPath: repo
        )

        await model.load()
        await model.selectPlanCommits()

        #expect(model.selectedEntryIDs == [
            "commit:\(phaseOneHash)",
            "commit:\(phaseTwoHash)",
        ])

        guard case .loaded(let diff) = model.diffState else {
            Issue.record("Expected a loaded diff after selecting plan commits.")
            return
        }
        #expect(diff.rawContent.contains("+phase two"))
    }

    private func cleanupRepository(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeRepository() async throws -> String {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CommitListDiffModelTests-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        // Run blocking git init on a background thread to avoid blocking the main actor,
        // which would stall Swift Testing's scheduler on CI.
        let pathCopy = path
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.currentDirectoryURL = URL(fileURLWithPath: pathCopy)
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["init"]
                process.standardError = Pipe()
                process.standardOutput = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        continuation.resume(throwing: TestFailure("git init failed in \(pathCopy)"))
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        _ = try await gitClient.config(key: "user.email", value: "tests@example.com", workingDirectory: path)
        _ = try await gitClient.config(key: "user.name", value: "Test User", workingDirectory: path)

        return path
    }

    private func stageAndCommit(repoPath: String, message: String) async throws {
        try await gitClient.addAll(workingDirectory: repoPath)
        try await gitClient.commit(message: message, workingDirectory: repoPath)
    }

    private func write(_ content: String, to repoPath: String, path: String) throws {
        let fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(path)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func runGit(arguments: [String], workingDirectory: String) throws {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardError = Pipe()
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw TestFailure("git \(arguments.joined(separator: " ")) failed in \(workingDirectory)")
        }
    }
}

private struct TestFailure: Error {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
