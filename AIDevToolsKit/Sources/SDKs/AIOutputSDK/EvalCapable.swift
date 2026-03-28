import Foundation
import SkillScannerSDK

public protocol EvalCapable: Sendable {
    var evalCapabilities: ProviderCapabilities { get }
    var streamFormatter: any StreamFormatter { get }

    func invocationMethod(
        for skillName: String,
        toolEvents: [ToolEvent],
        traceCommands: [String],
        skills: [SkillInfo],
        repoRoot: URL?
    ) -> InvocationMethod?

    func runEval(
        prompt: String,
        outputSchemaPath: URL,
        artifactsDirectory: URL,
        caseId: String,
        model: String?,
        workingDirectory: URL?,
        evalMode: EvalMode,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> EvalRunOutput
}
