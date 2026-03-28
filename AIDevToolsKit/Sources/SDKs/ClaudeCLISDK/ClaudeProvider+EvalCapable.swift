import AIOutputSDK
import Foundation
import SkillScannerSDK

extension ClaudeProvider: EvalCapable {

    public var evalCapabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsToolEventAssertions: true,
            supportsEventStream: true,
            supportsMetrics: true
        )
    }

    public var streamFormatter: any StreamFormatter {
        ClaudeStreamFormatter()
    }

    public func invocationMethod(
        for skillName: String,
        toolEvents: [ToolEvent],
        traceCommands: [String],
        skills: [SkillInfo],
        repoRoot: URL?
    ) -> InvocationMethod? {
        if toolEvents.contains(where: { $0.skillName == skillName }) { return .explicit }
        let prefixes = [".claude/skills/", ".agents/skills/"]
        let filePaths = toolEvents.compactMap(\.filePath)
        let matches = filePaths.contains { path in
            prefixes.contains { prefix in
                guard path.contains(prefix) else { return false }
                return path.contains("/\(skillName)/") || path.contains("/\(skillName).md")
            }
        }
        return matches ? .discovered : nil
    }

    public func runEval(
        prompt: String,
        outputSchemaPath: URL,
        artifactsDirectory: URL,
        caseId: String,
        model: String?,
        workingDirectory: URL?,
        evalMode: EvalMode,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> EvalRunOutput {
        let schemaData = try Data(contentsOf: outputSchemaPath)
        let schemaObject = try JSONSerialization.jsonObject(with: schemaData)
        let compactData = try JSONSerialization.data(withJSONObject: schemaObject, options: [.sortedKeys])
        let schemaJSON = String(data: compactData, encoding: .utf8) ?? ""

        let options = AIClientOptions(
            dangerouslySkipPermissions: evalMode == .edit,
            jsonSchema: schemaJSON,
            model: model,
            workingDirectory: workingDirectory?.path
        )

        let result = try await run(prompt: prompt, options: options, onOutput: onOutput)
        let providerResult = ClaudeOutputParser().buildResult(from: result.stdout, provider: Provider(client: self))

        return EvalRunOutput(result: providerResult, rawStdout: result.stdout, stderr: result.stderr)
    }
}
