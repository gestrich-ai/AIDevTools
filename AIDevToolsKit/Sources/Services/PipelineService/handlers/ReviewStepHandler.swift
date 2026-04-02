import AIOutputSDK
import CLISDK
import Foundation
import PipelineSDK

public struct ReviewStepHandler: StepHandler {
    private let client: any AIClient
    private let cliClient: CLIClient

    private static let reviewSchema = """
    {"type":"object","properties":{"fixes":{"type":"array","items":{"type":"object","properties":{"description":{"type":"string"},"prompt":{"type":"string"}},"required":["description","prompt"]}}},"required":["fixes"]}
    """

    public init(client: any AIClient, cliClient: CLIClient) {
        self.client = client
        self.cliClient = cliClient
    }

    public func execute(_ step: ReviewStepData, context: StepExecutionContext) async throws -> [any PipelineStep] {
        let diff = try await getGitDiff(scope: step.scope, workingDirectory: context.workingDirectory)

        let prompt = buildReviewPrompt(step: step, diff: diff)
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: context.workingDirectory
        )

        let result = try await client.runStructured(
            ReviewResult.self,
            prompt: prompt,
            jsonSchema: Self.reviewSchema,
            options: options,
            onOutput: nil
        )

        return result.value.fixes.enumerated().map { index, fix in
            CodeChangeStep(
                id: "\(step.id)-fix-\(index)",
                description: fix.description,
                isCompleted: false,
                prompt: fix.prompt,
                skills: [],
                context: .empty
            )
        }
    }

    private func buildReviewPrompt(step: ReviewStepData, diff: String) -> String {
        """
        \(step.prompt)

        Changes to review:
        \(diff.isEmpty ? "(no changes detected)" : diff)

        Return a JSON list of fixes required. Each fix should have:
        - description: A brief description of what needs to be fixed
        - prompt: A detailed prompt for an AI agent to implement the fix

        Return an empty fixes array if no changes are needed.
        """
    }

    private func getGitDiff(scope: ReviewScope, workingDirectory: String) async throws -> String {
        let arguments: [String]
        switch scope {
        case .allSinceLastReview:
            arguments = ["diff", "HEAD"]
        case .lastN(let n):
            arguments = ["diff", "HEAD~\(n)...HEAD"]
        case .stepIDs(_):
            // For now, fall back to diff HEAD since we don't have commit mapping for step IDs
            // TODO: Implement proper step ID to commit mapping
            arguments = ["diff", "HEAD"]
        }
        let result = try await cliClient.execute(
            command: "git",
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard result.isSuccess else {
            throw ReviewStepError.gitDiffFailed(
                arguments: arguments.joined(separator: " "),
                output: result.errorOutput
            )
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
