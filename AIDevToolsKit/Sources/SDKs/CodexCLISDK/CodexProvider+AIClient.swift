import AIOutputSDK
import CLISDK
import Foundation

extension CodexProvider: AIClient {
    public var name: String { "codex" }
    public var displayName: String { "Codex CLI" }

    public static let outputFileEnvironmentKey = "CODEX_OUTPUT_FILE"
    public static let outputSchemaPathEnvironmentKey = "CODEX_OUTPUT_SCHEMA_PATH"

    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        if let sessionId = options.sessionId {
            return try await runResume(sessionId: sessionId, prompt: prompt, options: options, onOutput: onOutput, onStreamEvent: onStreamEvent)
        }

        var command = Codex.Exec(prompt: prompt)
        command.color = "never"
        command.dangerouslyBypassApprovalsAndSandbox = options.dangerouslySkipPermissions
        command.json = true
        command.model = options.model
        command.skipGitRepoCheck = true
        if let outputFile = options.environment?[Self.outputFileEnvironmentKey] {
            command.outputFile = outputFile
        }
        if let schemaPath = options.environment?[Self.outputSchemaPathEnvironmentKey] {
            command.outputSchema = schemaPath
        } else if let jsonSchema = options.jsonSchema {
            command.outputSchema = jsonSchema
        }

        let stdoutCapture = StdoutAccumulator()
        let maxTimeoutRetries = 1
        var retryCount = 0

        while true {
            do {
                let result = try await run(
                    command: command,
                    workingDirectory: options.workingDirectory,
                    environment: options.environment,
                    onOutput: Self.outputHandler(stdoutCapture: stdoutCapture, onOutput: onOutput, onStreamEvent: onStreamEvent)
                )
                // Codex does not write session files or update session_index.jsonl when stdin is a
                // pipe (which CLIClient always uses). We write the index entry ourselves so sessions
                // appear in the history picker. The rollout file in ~/.codex/sessions/ will not exist
                // for these runs, so loading full message history from a past session is not supported.
                let sessionId = parseThreadId(from: result.stdout)
                if let id = sessionId, result.exitCode == 0 || result.exitCode == 143 {
                    let summary = String(prompt.prefix(80))
                    try? CodexSessionStorage().appendSession(id: id, threadName: summary)
                    // Swallowing intentionally: index write is best-effort. The session can still
                    // be resumed via thread_id; only the history list entry would be missing.
                }
                return AIClientResult(exitCode: result.exitCode, sessionId: sessionId, stderr: result.stderr, stdout: result.stdout)
            } catch let error as CodexCLIError {
                guard case .inactivityTimeout = error,
                      retryCount < maxTimeoutRetries,
                      let threadId = parseThreadId(from: stdoutCapture.content) else {
                    throw error
                }
                retryCount += 1
                return try await runResume(
                    sessionId: threadId,
                    prompt: "Continue where you left off.",
                    options: options,
                    onOutput: onOutput,
                    onStreamEvent: onStreamEvent
                )
            } catch is CancellationError {
                // Save session ID from partial stdout so the thread can be resumed after cancellation.
                // The thread.started event is emitted early, so it's already in stdoutCapture even when
                // the request is cancelled mid-response.
                if let threadId = parseThreadId(from: stdoutCapture.content) {
                    let summary = String(prompt.prefix(80))
                    try? CodexSessionStorage().appendSession(id: threadId, threadName: summary)
                }
                throw CancellationError()
            }
        }
    }

    private func runResume(
        sessionId: String,
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        var command = Codex.Exec.Resume(sessionId: sessionId, prompt: prompt)
        command.dangerouslyBypassApprovalsAndSandbox = options.dangerouslySkipPermissions
        command.json = true
        command.model = options.model
        command.skipGitRepoCheck = true
        let result = try await run(
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput,
            onStreamEvent: onStreamEvent
        )
        return AIClientResult(exitCode: result.exitCode, sessionId: sessionId, stderr: result.stderr, stdout: result.stdout)
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        var command = Codex.Exec(prompt: prompt)
        command.dangerouslyBypassApprovalsAndSandbox = options.dangerouslySkipPermissions
        command.ephemeral = true
        command.json = true
        command.model = options.model
        command.outputSchema = jsonSchema
        command.skipGitRepoCheck = true
        let result = try await run(
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput
        )
        let data = Data(result.stdout.utf8)
        let value = try JSONDecoder().decode(T.self, from: data)
        return AIStructuredResult(rawOutput: result.stdout, stderr: result.stderr, value: value)
    }

    // MARK: - Helpers

    private static func outputHandler(
        stdoutCapture: StdoutAccumulator,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) -> @Sendable (StreamOutput) -> Void {
        let formatter = CodexStreamFormatter()
        return { item in
            switch item {
            case .stdout(_, let text):
                stdoutCapture.append(text)
                let formatted = formatter.format(text)
                if !formatted.isEmpty {
                    onOutput?(formatted)
                }
                for event in formatter.formatStructured(text) {
                    onStreamEvent?(event)
                }
            case .stderr(_, let text):
                let formatted = formatter.format(text)
                if !formatted.isEmpty {
                    onOutput?(formatted)
                } else {
                    let nonJSON = text.components(separatedBy: "\n")
                        .filter { line in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            return !trimmed.isEmpty && !trimmed.hasPrefix("{")
                        }
                        .joined(separator: "\n")
                    if !nonJSON.isEmpty {
                        onOutput?(nonJSON)
                    }
                }
            default:
                break
            }
        }
    }

    private func parseThreadId(from stdout: String) -> String? {
        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(ThreadStartedEvent.self, from: data),
                  obj.type == "thread.started" else { continue }
            return obj.threadId
        }
        return nil
    }

    // MARK: - Session History

    public func listSessions(workingDirectory: String) async -> [ChatSession] {
        CodexSessionStorage().listSessions()
    }

    public func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        CodexSessionStorage().loadMessages(sessionId: sessionId)
    }

    public func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? {
        CodexSessionStorage().getSessionDetails(sessionId: sessionId, summary: summary, lastModified: lastModified)
    }
}

final class StdoutAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    var content: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += text
    }
}

private struct ThreadStartedEvent: Decodable {
    let type: String
    let threadId: String

    enum CodingKeys: String, CodingKey {
        case type
        case threadId = "thread_id"
    }
}
