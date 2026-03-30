import AIOutputSDK
import Foundation
import Testing
@testable import EvalService

private struct PassthroughFormatter: StreamFormatter {
    func format(_ rawChunk: String) -> String { rawChunk }
}

@Suite struct OutputServiceTests {

    private let service = OutputService()

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputServiceTests-\(UUID().uuidString)")
    }

    private func writeArtifacts(
        result: ProviderResult,
        stdout: String,
        stderr: String,
        provider: Provider = Provider(rawValue: "claude"),
        caseId: String = "test-case",
        outputDir: URL
    ) throws -> ProviderResult {
        let artifactsDir = OutputService.artifactsDirectory(outputDirectory: outputDir)
        let evalOutput = EvalRunOutput(result: result, rawStdout: stdout, stderr: stderr)
        return try service.writeEvalArtifacts(
            evalOutput: evalOutput,
            provider: provider,
            caseId: caseId,
            artifactsDirectory: artifactsDir
        )
    }

    @Test func writeAndReadRoundTrip() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let result = ProviderResult(provider: Provider(rawValue: "claude"))

        let updated = try writeArtifacts(result: result, stdout: "hello stdout", stderr: "hello stderr", outputDir: outputDir)
        let rawContents = try String(contentsOf: updated.rawStdoutPath!, encoding: .utf8)

        #expect(rawContents == "hello stdout")
    }

    @Test func writeCreatesStdoutAndStderrFiles() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let result = ProviderResult(provider: Provider(rawValue: "claude"))

        let updated = try writeArtifacts(result: result, stdout: "out", stderr: "err", outputDir: outputDir)

        #expect(updated.rawStdoutPath != nil)
        #expect(updated.rawStderrPath != nil)
        #expect(FileManager.default.fileExists(atPath: updated.rawStdoutPath!.path))
        #expect(FileManager.default.fileExists(atPath: updated.rawStderrPath!.path))
    }

    @Test func stdoutPathUsesExpectedLayout() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let result = ProviderResult(provider: Provider(rawValue: "claude"))

        let updated = try writeArtifacts(
            result: result,
            stdout: "content",
            stderr: "",
            provider: Provider(rawValue: "claude"),
            caseId: "my-suite.my-case",
            outputDir: outputDir
        )

        let expected = outputDir
            .appendingPathComponent("artifacts/raw/claude/my-suite.my-case.stdout")
        #expect(updated.rawStdoutPath == expected)
    }

    @Test func readMissingOutputThrows() {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        #expect(throws: OutputServiceError.self) {
            try service.readFormattedOutput(caseId: "missing", provider: Provider(rawValue: "claude"), outputDirectory: outputDir, formatter: PassthroughFormatter(), rubricFormatter: PassthroughFormatter())
        }
    }

    @Test func writeOverwritesPreviousOutput() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let result = ProviderResult(provider: Provider(rawValue: "claude"))

        _ = try writeArtifacts(result: result, stdout: "first", stderr: "", outputDir: outputDir)
        let updated = try writeArtifacts(result: result, stdout: "second", stderr: "", outputDir: outputDir)
        let rawContents = try String(contentsOf: updated.rawStdoutPath!, encoding: .utf8)

        #expect(rawContents == "second")
    }
}
