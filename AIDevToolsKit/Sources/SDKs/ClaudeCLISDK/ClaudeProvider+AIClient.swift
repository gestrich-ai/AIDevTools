import AIOutputSDK
import CLISDK

extension ClaudeProvider: AIClient {
    public var name: String { "claude" }
    public var displayName: String { "Claude CLI" }

    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        var command = Claude(prompt: prompt)
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        command.jsonSchema = options.jsonSchema
        command.mcpConfig = options.mcpConfigPath
        command.model = options.model
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.resume = options.sessionId
        command.systemPrompt = options.systemPrompt
        command.verbose = true

        let stdoutCapture = StdoutAccumulator()
        let formatter = ClaudeStreamFormatter()

        do {
            let result = try await run(
                command: command,
                workingDirectory: options.workingDirectory,
                environment: options.environment,
                onOutput: { item in
                    switch item {
                    case .stdout(_, let text):
                        stdoutCapture.append(text)
                        if let onOutput {
                            let formatted = formatter.format(text)
                            if !formatted.isEmpty { onOutput(formatted) }
                        }
                        if let onStreamEvent {
                            for event in formatter.formatStructured(text) {
                                onStreamEvent(event)
                            }
                        }
                    case .stderr(_, let text):
                        if let onOutput {
                            let nonJSON = text.components(separatedBy: "\n")
                                .filter { line in
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    return !trimmed.isEmpty && !trimmed.hasPrefix("{")
                                }
                                .joined(separator: "\n")
                            if !nonJSON.isEmpty { onOutput(nonJSON) }
                        }
                    default:
                        break
                    }
                }
            )
            let sessionId = Self.extractSessionId(from: result.stdout)
            return AIClientResult(exitCode: result.exitCode, sessionId: sessionId, stderr: result.stderr, stdout: result.stdout)
        } catch is CancellationError {
            // Claude writes its own session file to disk, but it may not be flushed by the
            // time ChatModel calls listSessions(). Storing the session_id from partial stdout
            // into our own index makes recovery reliable without depending on file-system timing.
            if let sessionId = Self.extractSessionId(from: stdoutCapture.content) {
                try? ClaudeSessionIndex().appendSession(id: sessionId, summary: String(prompt.prefix(80)))
            }
            throw CancellationError()
        }
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        var command = Claude(prompt: prompt)
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        command.jsonSchema = jsonSchema
        command.mcpConfig = options.mcpConfigPath
        command.model = options.model
        command.resume = options.sessionId
        command.systemPrompt = options.systemPrompt
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.printMode = true
        command.verbose = true
        let output = try await runStructured(
            T.self,
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput,
            onStreamEvent: onStreamEvent
        )
        let sessionId = Self.extractSessionId(from: output.rawOutput)
        return AIStructuredResult(rawOutput: output.rawOutput, sessionId: sessionId, stderr: output.stderr, value: output.value)
    }
}
