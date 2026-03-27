import AIOutputSDK
import Foundation
@preconcurrency import SwiftAnthropic

public actor AnthropicAIClient: AIClient {
    private let apiClient: AnthropicAPIClient
    private var conversations: [String: [MessageParameter.Message]] = [:]

    public init(apiClient: AnthropicAPIClient) {
        self.apiClient = apiClient
    }

    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult {
        let sessionId = options.sessionId ?? UUID().uuidString
        var history = conversations[sessionId] ?? []

        let userMessage = MessageParameter.Message(role: .user, content: .text(prompt))
        history.append(userMessage)

        let model: SwiftAnthropic.Model = options.model.map { .other($0) } ?? .other("claude-sonnet-4-20250514")
        let parameters = MessageParameter(
            model: model,
            messages: history,
            maxTokens: 4096,
            system: options.systemPrompt.map { .text($0) },
            metadata: nil,
            stopSequences: nil,
            stream: true,
            temperature: nil,
            topK: nil,
            topP: nil,
            tools: nil,
            toolChoice: nil,
            thinking: nil
        )

        let stream = try await apiClient.streamMessage(parameters)
        var fullResponse = ""

        for try await chunk in stream {
            if let delta = chunk.delta, let text = delta.text {
                fullResponse += text
                onOutput?(text)
            }
        }

        let assistantMessage = MessageParameter.Message(role: .assistant, content: .text(fullResponse))
        history.append(assistantMessage)
        conversations[sessionId] = history

        return AIClientResult(exitCode: 0, sessionId: sessionId, stderr: "", stdout: fullResponse)
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        let structuredPrompt = """
            \(prompt)

            You MUST respond with valid JSON matching this schema:
            \(jsonSchema)

            Respond ONLY with the JSON object, no other text.
            """

        let result = try await run(prompt: structuredPrompt, options: options, onOutput: onOutput)

        let data = Data(result.stdout.utf8)
        let value = try JSONDecoder().decode(T.self, from: data)

        return AIStructuredResult(rawOutput: result.stdout, sessionId: result.sessionId, stderr: "", value: value)
    }
}
