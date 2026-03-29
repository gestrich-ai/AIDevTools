import Foundation
import PipelineSDK

public struct ExecutePipelineUseCase: Sendable {

    public struct Options: Sendable {
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

    public struct Result: Sendable {
        public let stepsExecuted: Int
        public let allCompleted: Bool

        public init(stepsExecuted: Int, allCompleted: Bool) {
            self.stepsExecuted = stepsExecuted
            self.allCompleted = allCompleted
        }
    }

    public enum Progress: Sendable {
        case stepStarted(stepDescription: String, index: Int, total: Int)
        case stepOutput(text: String)
        case stepCompleted(stepDescription: String, index: Int)
        case stepsAppended(count: Int)
        case allCompleted(stepsExecuted: Int)
    }

    public enum ExecuteError: Error, LocalizedError {
        case noHandlerFound(stepDescription: String)

        public var errorDescription: String? {
            switch self {
            case .noHandlerFound(let desc):
                return "No handler registered for step: \(desc)"
            }
        }
    }

    public init() {}

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        let pipeline = try await options.source.load()

        // Seed the local mutable array — the execution loop appends dynamic steps here
        var localSteps: [any PipelineStep] = pipeline.steps
        let currentContext = options.context
        var stepsExecuted = 0
        var index = 0

        while index < localSteps.count {
            let step = localSteps[index]

            guard !step.isCompleted else {
                index += 1
                continue
            }

            onProgress?(.stepStarted(
                stepDescription: step.description,
                index: index,
                total: localSteps.count
            ))

            // Dispatch to the first handler that accepts this step type
            var newSteps: [any PipelineStep] = []
            var handled = false
            for handler in options.handlers {
                if let result = try await handler.tryExecute(step, context: currentContext) {
                    newSteps = result
                    handled = true
                    break
                }
            }

            guard handled else {
                throw ExecuteError.noHandlerFound(stepDescription: step.description)
            }

            // Persist completion before moving on
            try await options.source.markStepCompleted(step)
            stepsExecuted += 1
            onProgress?(.stepCompleted(stepDescription: step.description, index: index))

            // Append dynamic steps emitted by the handler
            if !newSteps.isEmpty {
                localSteps.append(contentsOf: newSteps)
                try await options.source.appendSteps(newSteps)
                onProgress?(.stepsAppended(count: newSteps.count))
            }

            index += 1
        }

        onProgress?(.allCompleted(stepsExecuted: stepsExecuted))
        return Result(stepsExecuted: stepsExecuted, allCompleted: true)
    }
}
