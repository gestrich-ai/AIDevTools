import Foundation
import PipelineSDK
import PipelineService

public struct ExecutePipelineOptions: Sendable {
    public let source: any PipelineSource
    public let context: PipelineContext
    public let handlers: [AnyStepHandler]

    public init(
        source: any PipelineSource,
        context: PipelineContext,
        handlers: [AnyStepHandler]
    ) {
        self.source = source
        self.context = context
        self.handlers = handlers
    }
}