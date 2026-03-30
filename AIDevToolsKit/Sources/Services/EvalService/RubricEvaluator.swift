import AIOutputSDK
import Foundation

public struct RubricEvaluator: Sendable {

    private let promptBuilder: PromptBuilder
    private let rubricGrader: RubricGrader
    private let outputService: OutputService

    public init(
        promptBuilder: PromptBuilder = PromptBuilder(),
        rubricGrader: RubricGrader = RubricGrader(),
        outputService: OutputService = OutputService()
    ) {
        self.promptBuilder = promptBuilder
        self.rubricGrader = rubricGrader
        self.outputService = outputService
    }

    public func evaluate(
        rubric: RubricConfig,
        evalCase: EvalCase,
        caseId: String,
        resultText: String,
        client: any AIClient & EvalCapable,
        rubricSchemaPath: URL,
        artifactsDirectory: URL,
        provider: Provider,
        model: String?,
        repoRoot: URL
    ) async throws -> [String] {
        let rubricPrompt = promptBuilder.renderTemplate(
            rubric.prompt,
            case: evalCase,
            resultText: resultText,
            repoRoot: repoRoot
        )

        let schemaPath: URL
        if let customSchemaPath = rubric.schemaPath {
            schemaPath = repoRoot.appendingPathComponent(customSchemaPath)
        } else {
            schemaPath = rubricSchemaPath
        }

        let rubricCaseId = "\(caseId).rubric"
        let evalOutput = try await client.runEval(
            prompt: rubricPrompt,
            outputSchemaPath: schemaPath,
            artifactsDirectory: artifactsDirectory,
            caseId: rubricCaseId,
            model: model,
            workingDirectory: repoRoot,
            evalMode: .structured,
            onOutput: nil
        )

        let result = try outputService.writeEvalArtifacts(
            evalOutput: evalOutput,
            provider: provider,
            caseId: rubricCaseId,
            artifactsDirectory: artifactsDirectory
        )

        if let error = result.error {
            return ["rubric provider error: \(error.message)"]
        }

        guard let rubricOutput = result.structuredOutput else {
            return ["rubric returned no structured output"]
        }

        return rubricGrader.gradeFromJSON(case: evalCase, rubricPayload: rubricOutput)
    }
}
