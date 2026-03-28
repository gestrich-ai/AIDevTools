import AIOutputSDK
import Foundation

public struct ClaudeResultEvent: Codable, Sendable {
    public let type: String
    public let isError: Bool?
    public let subtype: String?
    public let errors: JSONValue?
    public let structuredOutput: [String: JSONValue]?
    public let durationMs: Int?
    public let totalCostUsd: Double?
    public let numTurns: Int?
    public let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case isError = "is_error"
        case subtype
        case errors
        case structuredOutput = "structured_output"
        case durationMs = "duration_ms"
        case totalCostUsd = "total_cost_usd"
        case numTurns = "num_turns"
        case sessionId = "session_id"
    }

    public var diagnosticSummary: String {
        var parts: [String] = []
        if let sessionId { parts.append("session=\(sessionId)") }
        if let isError { parts.append("is_error=\(isError)") }
        if let subtype { parts.append("subtype=\(subtype)") }
        if let numTurns { parts.append("turns=\(numTurns)") }
        if let durationMs { parts.append("duration=\(durationMs)ms") }
        if let totalCostUsd { parts.append(String(format: "cost=$%.4f", totalCostUsd)) }
        return "[\(parts.joined(separator: ", "))]"
    }

    public var metrics: ProviderMetrics {
        ProviderMetrics(durationMs: durationMs, costUsd: totalCostUsd, turns: numTurns)
    }

    public var providerError: ProviderError? {
        guard isError == true else { return nil }
        let message = errors.map { "\($0)" } ?? subtype ?? "unknown error"
        return ProviderError(
            message: message,
            subtype: subtype,
            details: errors.map { ["errors": $0] }
        )
    }
}
