import Foundation
import PipelineSDK
import PipelineService

public struct ExecutePipelineOptions: Sendable {
    public let source: any PipelineSource
    public let context: StepExecutionContext
    public let handlers: [AnyStepHandler]

    public init(
        source: any PipelineSource,
        context: StepExecutionContext,
        handlers: [AnyStepHandler]
    ) {
        self.source = source
        self.context = context
        self.handlers = handlers
    }
}
