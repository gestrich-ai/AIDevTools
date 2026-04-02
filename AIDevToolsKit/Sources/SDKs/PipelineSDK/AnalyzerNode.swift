import AIOutputSDK

public struct AnalyzerNode<Input: Sendable, Output: Decodable & Sendable>: PipelineNode {
    public static var outputKey: PipelineContextKey<Output> { .init("AnalyzerNode.output.\(Output.self)") }

    public let buildPrompt: @Sendable (Input) -> String
    public let client: any AIClient
    public let displayName: String
    public let id: String
    public let inputKey: PipelineContextKey<Input>
    public let jsonSchema: String

    public init(
        id: String,
        displayName: String,
        inputKey: PipelineContextKey<Input>,
        buildPrompt: @escaping @Sendable (Input) -> String,
        jsonSchema: String,
        client: any AIClient
    ) {
        self.buildPrompt = buildPrompt
        self.client = client
        self.displayName = displayName
        self.id = id
        self.inputKey = inputKey
        self.jsonSchema = jsonSchema
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        guard let input = context[inputKey] else {
            throw PipelineError.missingContextValue(key: inputKey.name)
        }

        let prompt = buildPrompt(input)
        let options = AIClientOptions(dangerouslySkipPermissions: true)

        let result = try await client.runStructured(
            Output.self,
            prompt: prompt,
            jsonSchema: jsonSchema,
            options: options,
            onOutput: { text in onProgress(.output(text)) },
            onStreamEvent: nil
        )

        var updated = context
        updated[Self.outputKey] = result.value
        return updated
    }
}
