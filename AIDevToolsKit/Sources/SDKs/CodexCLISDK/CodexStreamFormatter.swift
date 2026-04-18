import AIOutputSDK
import Foundation

// @unchecked Sendable: safe because CodexProvider always calls formatStructured() from a
// single serial async sequence (the onOutput closure in executeCodex), never concurrently.
public final class CodexStreamFormatter: StreamFormatter, @unchecked Sendable {
    private let decoder = JSONDecoder()
    // Holds the most recent agent_message until the next event clarifies its role:
    // - flushed as .thinking if a tool call follows
    // - flushed as .textDelta if turn.completed follows (it's the final answer)
    private var pendingAgentMessage: String?

    public init() {}

    public func format(_ rawChunk: String) -> String {
        var output = ""
        for line in rawChunk.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let formatted = formatLine(data) {
                output += formatted
            }
        }
        return output
    }

    private func formatLine(_ data: Data) -> String? {
        guard let event = try? decoder.decode(CodexFormatterEvent.self, from: data) else { return nil }

        switch event.type {
        case "item.completed":
            return formatItem(event.item)
        case "turn.completed":
            return formatTurnCompleted(event.usage)
        default:
            return nil
        }
    }

    private func formatItem(_ item: CodexFormatterItem?) -> String? {
        guard let item else { return nil }
        switch item.type {
        case "agent_message":
            if let text = item.text, !text.isEmpty {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
                   let wrapped = try? decoder.decode(CodexResultWrapper.self, from: data),
                   let result = wrapped.result, !result.isEmpty {
                    return result + "\n"
                } else if trimmed.hasPrefix("{") {
                    return nil
                }
                return text + "\n"
            }
        case "command_execution":
            var parts: [String] = []
            if let cmd = item.command {
                parts.append("[Command] \(cmd)")
            }
            if let output = item.aggregatedOutput, !output.isEmpty {
                parts.append(output)
            }
            if let exit = item.exitCode, exit != 0 {
                parts.append("Exit code: \(exit)")
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n") + "\n"
            }
        default:
            break
        }
        return nil
    }

    private func formatTurnCompleted(_ usage: CodexFormatterUsage?) -> String? {
        guard let usage else { return nil }
        var parts: [String] = ["--- Turn Complete ---"]
        if let input = usage.inputTokens {
            parts.append("Input: \(input) tokens")
        }
        if let output = usage.outputTokens {
            parts.append("Output: \(output) tokens")
        }
        return parts.joined(separator: " | ") + "\n"
    }

    // MARK: - Structured Parsing

    public func formatStructured(_ rawChunk: String) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for line in rawChunk.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            events.append(contentsOf: parseStreamEvents(data))
        }
        return events
    }

    private func parseStreamEvents(_ data: Data) -> [AIStreamEvent] {
        guard let event = try? decoder.decode(CodexFormatterEvent.self, from: data) else { return [] }

        switch event.type {
        case "item.completed":
            return parseItemStreamEvents(event.item)
        case "thread.started":
            if let id = event.threadId {
                return [.sessionStarted(id)]
            }
            return []
        case "turn.completed":
            // The held agent_message is the final answer — flush as textDelta then emit metrics.
            var events: [AIStreamEvent] = []
            if let text = flushPendingAsTextDelta() {
                events.append(.textDelta(text))
            }
            events.append(.metrics(duration: nil, cost: nil, turns: nil))
            return events
        default:
            return []
        }
    }

    private func parseItemStreamEvents(_ item: CodexFormatterItem?) -> [AIStreamEvent] {
        guard let item else { return [] }
        switch item.type {
        case "agent_message":
            guard let text = item.text, !text.isEmpty else { return [] }
            // Flush the previously held message as .thinking, then hold this one.
            var events: [AIStreamEvent] = []
            if let prev = pendingAgentMessage {
                events.append(.thinking(prev))
            }
            pendingAgentMessage = text
            return events
        case "command_execution":
            // A tool call confirms the held message was commentary — flush as .thinking.
            var events: [AIStreamEvent] = []
            if let text = pendingAgentMessage {
                events.append(.thinking(text))
                pendingAgentMessage = nil
            }
            let command = item.command ?? ""
            let output = item.aggregatedOutput ?? ""
            let isError = (item.exitCode ?? 0) != 0
            events.append(.toolUse(name: "bash", detail: command))
            events.append(.toolResult(name: "bash", summary: output, isError: isError))
            return events
        default:
            return []
        }
    }

    private func flushPendingAsTextDelta() -> String? {
        guard let text = pendingAgentMessage else { return nil }
        pendingAgentMessage = nil
        // Unwrap {"result":"..."} from structured output runs.
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let wrapped = try? decoder.decode(CodexResultWrapper.self, from: data),
           let result = wrapped.result {
            return result
        }
        return text
    }
}

private struct CodexResultWrapper: Decodable {
    let result: String?
}

private struct CodexFormatterEvent: Codable {
    let item: CodexFormatterItem?
    let threadId: String?
    let type: String
    let usage: CodexFormatterUsage?

    enum CodingKeys: String, CodingKey {
        case item, type, usage
        case threadId = "thread_id"
    }
}

private struct CodexFormatterItem: Codable {
    let type: String
    let text: String?
    let command: String?
    let aggregatedOutput: String?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case type, text, command
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
    }
}

private struct CodexFormatterUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
