public protocol PipelineSource: Sendable {
    func load() async throws -> PipelineState
    func markStepCompleted(_ step: any PipelineStep) async throws
    func appendSteps(_ steps: [any PipelineStep]) async throws
}
