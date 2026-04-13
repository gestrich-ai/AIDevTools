import Foundation

public struct PipelineRunner: Sendable {

    public init() {}

    public func run(
        nodes: [any PipelineNode],
        configuration: PipelineConfiguration,
        startingAt startIndex: Int = 0,
        initialContext: PipelineContext = PipelineContext(),
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        var context = initialContext
        if let workingDirectory = configuration.workingDirectory {
            context[PipelineContext.workingDirectoryKey] = workingDirectory
        }
        let startTime = Date()

        for (index, node) in nodes.enumerated() {
            guard index >= startIndex else { continue }
            guard !Task.isCancelled else { break }

            if let maxMinutes = configuration.maxMinutes {
                let elapsed = Date().timeIntervalSince(startTime) / 60
                if elapsed >= Double(maxMinutes) { break }
            }

            onProgress(.nodeStarted(id: node.id, displayName: node.displayName))

            if node is ReviewStep {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    onProgress(.pausedForReview(continuation: continuation))
                }
            } else {
                let nodeID = node.id
                context = try await node.run(context: context) { progress in
                    onProgress(.nodeProgress(id: nodeID, progress: progress))
                }
            }

            onProgress(.nodeCompleted(id: node.id, displayName: node.displayName))
            // Yield between nodes so tasks that were spawned from onProgress
            // (e.g. pipeline.stop()) get a chance to run before the next node starts.
            await Task.yield()

            if let injectedSource = context[PipelineContext.injectedTaskSourceKey] {
                context[PipelineContext.injectedTaskSourceKey] = nil
                context = try await drainTaskSource(injectedSource, configuration: configuration, context: context, onProgress: onProgress)
            }
        }

        onProgress(.completed(context: context))
        return context
    }

    // MARK: - Private

    private func drainTaskSource(
        _ source: any TaskSource,
        configuration: PipelineConfiguration,
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        var context = context
        var nextTask = try await source.nextTask()
        if let task = nextTask {
            onProgress(.taskDiscovered(id: task.id, displayName: task.id))
        }
        while let task = nextTask {
            guard !Task.isCancelled else { break }

            let taskNode = AITask<String>(
                id: task.id,
                displayName: task.displayName,
                instructions: task.instructions,
                client: configuration.provider,
                workingDirectory: context[PipelineContext.workingDirectoryKey] ?? configuration.workingDirectory,
                environment: configuration.environment
            )

            onProgress(.nodeStarted(id: taskNode.id, displayName: taskNode.displayName))
            let taskNodeID = taskNode.id
            context = try await taskNode.run(context: context) { progress in
                onProgress(.nodeProgress(id: taskNodeID, progress: progress))
            }
            onProgress(.nodeCompleted(id: taskNode.id, displayName: taskNode.displayName))

            try await source.markComplete(task)

            if configuration.executionMode == .nextOnly { break }

            nextTask = try await source.nextTask()
            if let next = nextTask {
                onProgress(.taskDiscovered(id: next.id, displayName: next.id))
                try await configuration.betweenTasks?()
            }
        }
        return context
    }
}
