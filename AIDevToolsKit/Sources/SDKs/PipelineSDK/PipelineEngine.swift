import Foundation

public actor Pipeline {
    private let nodes: [any PipelineNode]
    private let configuration: PipelineConfiguration
    private var context: PipelineContext
    private var isStopped = false
    private var reviewContinuation: CheckedContinuation<Void, any Error>?

    public init(
        nodes: [any PipelineNode],
        configuration: PipelineConfiguration,
        initialContext: PipelineContext = PipelineContext()
    ) {
        self.context = initialContext
        self.configuration = configuration
        self.nodes = nodes
    }

    public func run(
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        return try await run(startingAt: 0, onProgress: onProgress)
    }

    public func run(
        startingAt startIndex: Int,
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        isStopped = false
        let startTime = Date()

        for (index, node) in nodes.enumerated() {
            guard index >= startIndex else { continue }
            guard !isStopped else { break }

            if let maxMinutes = configuration.maxMinutes {
                let elapsed = Date().timeIntervalSince(startTime) / 60
                if elapsed >= Double(maxMinutes) { break }
            }

            onProgress(.nodeStarted(id: node.id, displayName: node.displayName))

            if node is ReviewStep {
                onProgress(.pausedForReview)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    self.reviewContinuation = continuation
                }
            } else {
                let nodeID = node.id
                context = try await node.run(context: context) { progress in
                    onProgress(.nodeProgress(id: nodeID, progress: progress))
                }
            }

            onProgress(.nodeCompleted(id: node.id, displayName: node.displayName))

            if let injectedSource = context[PipelineContext.injectedTaskSourceKey] {
                context[PipelineContext.injectedTaskSourceKey] = nil
                try await drainTaskSource(injectedSource, onProgress: onProgress)
            }
        }

        onProgress(.completed(context: context))
        return context
    }

    public func stop() {
        isStopped = true
    }

    public func approve() {
        reviewContinuation?.resume()
        reviewContinuation = nil
    }

    public func cancel() {
        reviewContinuation?.resume(throwing: PipelineError.cancelled)
        reviewContinuation = nil
    }

    // MARK: - Private

    private func drainTaskSource(
        _ source: any TaskSource,
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws {
        while let task = try await source.nextTask() {
            guard !isStopped else { break }

            let taskNode = AITask<String>(
                id: task.id,
                displayName: String(task.instructions.prefix(60)),
                instructions: task.instructions,
                client: configuration.provider,
                jsonSchema: nil
            )

            onProgress(.nodeStarted(id: taskNode.id, displayName: taskNode.displayName))
            let taskNodeID = taskNode.id
            context = try await taskNode.run(context: context) { progress in
                onProgress(.nodeProgress(id: taskNodeID, progress: progress))
            }
            onProgress(.nodeCompleted(id: taskNode.id, displayName: taskNode.displayName))

            try await source.markComplete(task)

            if configuration.executionMode == .nextOnly { break }
        }
    }
}
