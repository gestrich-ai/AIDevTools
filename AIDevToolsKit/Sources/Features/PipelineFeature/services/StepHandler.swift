import PipelineSDK

public protocol StepHandler: Sendable {
    associatedtype Step: PipelineStep
    func execute(_ step: Step, context: PipelineContext) async throws -> [any PipelineStep]
}
