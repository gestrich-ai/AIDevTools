import AIOutputSDK
import EvalService
import Foundation
import SkillScannerSDK

public struct CodexAdapter: ProviderAdapterProtocol {

    private let client: any AIClient
    private let parser = CodexOutputParser()
    private let outputService = OutputService()

    public init(client: any AIClient) {
        self.client = client
    }

    public func capabilities() -> ProviderCapabilities {
        ProviderCapabilities(
            supportsToolEventAssertions: true,
            supportsEventStream: true,
            supportsMetrics: false
        )
    }

    public func invocationMethod(for skillName: String, toolEvents: [ToolEvent], traceCommands: [String], skills: [SkillInfo], repoRoot: URL?) -> InvocationMethod? {
        if let skillInfo = skills.first(where: { $0.name == skillName }), let repoRoot {
            let relativePath = skillInfo.relativePath(to: repoRoot)
            if traceCommands.contains(where: { $0.contains(relativePath) }) { return .inferred }
        }
        let prefixes = [".claude/skills/", ".agents/skills/"]
        let matches = traceCommands.contains { cmd in
            prefixes.contains { prefix in
                guard cmd.contains(prefix) else { return false }
                return cmd.contains("/\(skillName)/") || cmd.contains("/\(skillName).md")
            }
        }
        return matches ? .inferred : nil
    }

    public func run(configuration: RunConfiguration, onOutput: (@Sendable (String) -> Void)? = nil) async throws -> ProviderResult {
        let outputFile = configuration.providerDirectory.appendingPathComponent("\(configuration.caseId).json")
        try FileManager.default.createDirectory(at: configuration.providerDirectory, withIntermediateDirectories: true)

        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            environment: [
                "CODEX_OUTPUT_FILE": outputFile.path,
                "CODEX_OUTPUT_SCHEMA_PATH": configuration.outputSchemaPath.path,
            ],
            model: configuration.model,
            workingDirectory: configuration.workingDirectory?.path
        )

        let session = OutputService.makeSession(
            artifactsDirectory: configuration.artifactsDirectory,
            provider: configuration.provider.rawValue,
            caseId: configuration.caseId,
            client: client
        )

        let result = try await session.run(
            prompt: configuration.prompt,
            options: options,
            onOutput: onOutput
        )

        guard result.exitCode == 0 else {
            let trimmedStderr = result.stderr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let trimmedStdout = result.stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let errorMessage = trimmedStderr.isEmpty ? trimmedStdout : trimmedStderr
            let errorResult = ProviderResult(
                provider: .codex,
                error: ProviderError(message: errorMessage, subtype: ProviderErrorSubtype.execFailed)
            )
            return try outputService.writeArtifacts(
                result: errorResult,
                stderr: result.stderr,
                session: session,
                configuration: configuration
            )
        }

        var providerResult = parser.buildResult(from: result.stdout)

        do {
            let data = try Data(contentsOf: outputFile)
            let payload = try JSONDecoder().decode([String: JSONValue].self, from: data)
            providerResult.structuredOutput = payload
            providerResult.resultText = payload[StructuredOutputKey.result]?.stringValue ?? ""
        } catch {
            providerResult.error = ProviderError(
                message: "invalid primary output JSON: \(error.localizedDescription)",
                subtype: ProviderErrorSubtype.parseError
            )
        }

        return try outputService.writeArtifacts(
            result: providerResult,
            stderr: result.stderr,
            session: session,
            configuration: configuration
        )
    }

}
