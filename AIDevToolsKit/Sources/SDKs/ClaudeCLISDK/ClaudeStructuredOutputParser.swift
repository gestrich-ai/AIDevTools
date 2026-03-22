import Foundation

public struct ClaudeStructuredOutput<T: Sendable>: Sendable {
    public let value: T
    public let resultEvent: ClaudeResultEvent
}

public enum ClaudeStructuredOutputError: Error, LocalizedError {
    case noResultEvent
    case resultError(resultEvent: ClaudeResultEvent)
    case missingStructuredOutput(resultEvent: ClaudeResultEvent)
    case decodingFailed(Error, resultEvent: ClaudeResultEvent)

    public var errorDescription: String? {
        switch self {
        case .noResultEvent:
            return "Claude CLI returned no result event. The process may have exited early or produced no output."
        case .resultError(let resultEvent):
            var parts = ["Claude CLI returned an error"]
            if let subtype = resultEvent.subtype { parts.append("(\(subtype))") }
            if let errors = resultEvent.errors { parts.append(": \(errors)") }
            parts.append(resultEvent.diagnosticSummary)
            return parts.joined(separator: " ")
        case .missingStructuredOutput(let resultEvent):
            return "Claude CLI result contained no structured output. \(resultEvent.diagnosticSummary)"
        case .decodingFailed(let error, let resultEvent):
            return "Failed to decode Claude CLI response: \(error.localizedDescription). \(resultEvent.diagnosticSummary)"
        }
    }
}

public struct ClaudeStructuredOutputParser: Sendable {

    public init() {}

    public func parse<T: Decodable & Sendable>(_ type: T.Type, from stdout: String) throws -> ClaudeStructuredOutput<T> {
        let resultEvent = try findResultEvent(in: stdout)

        // Use subtype as the authoritative success signal, matching claude-code-action behavior.
        // The is_error field should align with subtype but is not the primary indicator.
        if resultEvent.subtype != "success" {
            throw ClaudeStructuredOutputError.resultError(resultEvent: resultEvent)
        }

        guard let structuredJSON = resultEvent.structuredOutput else {
            throw ClaudeStructuredOutputError.missingStructuredOutput(resultEvent: resultEvent)
        }

        let encoded = try JSONEncoder().encode(structuredJSON)
        do {
            let decoded = try JSONDecoder().decode(T.self, from: encoded)
            return ClaudeStructuredOutput(value: decoded, resultEvent: resultEvent)
        } catch {
            throw ClaudeStructuredOutputError.decodingFailed(error, resultEvent: resultEvent)
        }
    }

    public func findResultEvent(in stdout: String) throws -> ClaudeResultEvent {
        let decoder = JSONDecoder()
        var lastResult: ClaudeResultEvent?

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            guard let raw = try? decoder.decode([String: JSONValue].self, from: data),
                  raw["type"]?.stringValue == ClaudeEventType.result else { continue }

            if let event = try? decoder.decode(ClaudeResultEvent.self, from: data) {
                lastResult = event
            }
        }

        guard let result = lastResult else {
            throw ClaudeStructuredOutputError.noResultEvent
        }
        return result
    }
}
