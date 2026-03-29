import PipelineSDK

/// Type-erased wrapper so multiple concrete `StepHandler` implementations can be stored
/// together and dispatched by the executor.
public struct AnyStepHandler: Sendable {
    private let _tryExecute: @Sendable (any PipelineStep, PipelineContext) async throws -> [any PipelineStep]?

    public init<H: StepHandler>(_ handler: H) {
        _tryExecute = { step, context in
            guard let typedStep = step as? H.Step else { return nil }
            return try await handler.execute(typedStep, context: context)
        }
    }

    /// Returns `nil` if this handler does not handle the given step type.
    func tryExecute(_ step: any PipelineStep, context: PipelineContext) async throws -> [any PipelineStep]? {
        try await _tryExecute(step, context)
    }
}