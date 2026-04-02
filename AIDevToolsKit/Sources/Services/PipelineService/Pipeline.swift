import PipelineSDK

public actor Pipeline {
    private let nodes: [any PipelineNode]
    private let configuration: PipelineConfiguration
    private let initialContext: PipelineContext
    private var runTask: Task<PipelineContext, any Error>?

    public init(
        nodes: [any PipelineNode],
        configuration: PipelineConfiguration,
        initialContext: PipelineContext = PipelineContext()
    ) {
        self.configuration = configuration
        self.initialContext = initialContext
        self.nodes = nodes
    }

    public func run(
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        try await run(startingAt: 0, onProgress: onProgress)
    }

    public func run(
        startingAt startIndex: Int,
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        let nodes = self.nodes
        let configuration = self.configuration
        let initialContext = self.initialContext
        let task = Task {
            try await PipelineRunner().run(
                nodes: nodes,
                configuration: configuration,
                startingAt: startIndex,
                initialContext: initialContext,
                onProgress: onProgress
            )
        }
        runTask = task
        defer { runTask = nil }
        return try await task.value
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
    }
}
