import AIOutputSDK
import Foundation
import PipelineSDK

public struct CodeChangeStepHandler: StepHandler {
    private let client: any AIClient
    private let onOutput: (@Sendable (String) -> Void)?

    public init(client: any AIClient, onOutput: (@Sendable (String) -> Void)?) {
        self.client = client
        self.onOutput = onOutput
    }

    public func execute(_ step: CodeChangeStep, context: PipelineContext) async throws -> [any PipelineStep] {
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: context.workingDirectory
        )
        let result = try await client.run(
            prompt: step.prompt,
            options: options,
            onOutput: onOutput
        )
        
        // Check if the AI operation was successful
        guard result.exitCode == 0 else {
            throw CodeChangeError.executionFailed(
                stepId: step.id,
                stderr: result.stderr
            )
        }
        
        return []
    }
}

enum CodeChangeError: Error, LocalizedError {
    case executionFailed(stepId: String, stderr: String)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let stepId, let stderr):
            return "Code change step \(stepId) failed: \(stderr)"
        }
    }
}
