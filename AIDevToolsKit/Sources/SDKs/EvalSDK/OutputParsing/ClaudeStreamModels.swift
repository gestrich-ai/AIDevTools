import EvalService
import Foundation

enum ClaudeEventType {
    static let assistant = "assistant"
    static let result = "result"
    static let user = "user"
}

enum ClaudeContentBlockType {
    static let toolUse = "tool_use"
}

enum ClaudeContentBlockType2 {
    static let toolResult = "tool_result"
}

enum ClaudeToolName {
    static let bash = "Bash"
    static let filePath = "file_path"
    static let read = "Read"
    static let skill = "Skill"
    static let structuredOutput = "StructuredOutput"
}

enum ClaudeToolInputKey {
    static let command = "command"
    static let filePath = "file_path"
    static let skill = "skill"
}

struct ClaudeAssistantEvent: Codable, Sendable {
    let type: String
    let message: ClaudeMessage?
}

struct ClaudeMessage: Codable, Sendable {
    let content: [ClaudeContentBlock]?
}

struct ClaudeContentBlock: Codable, Sendable {
    let type: String
    let id: String?
    let text: String?
    let thinking: String?
    let name: String?
    let input: [String: JSONValue]?
    let content: ToolResultContent?
}

enum ToolResultContent: Codable, Sendable {
    case string(String)
    case array([[String: JSONValue]])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([[String: JSONValue]].self) {
            self = .array(arr)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .array(let arr):
            try container.encode(arr)
        }
    }

    var summary: String? {
        switch self {
        case .string(let str):
            return str.isEmpty ? nil : String(str.prefix(200))
        case .array:
            return nil
        }
    }
}

struct ClaudeUserEvent: Codable, Sendable {
    let type: String
    let message: ClaudeUserMessage?
}

struct ClaudeUserMessage: Codable, Sendable {
    let content: [ClaudeUserContentBlock]?
}

struct ClaudeUserContentBlock: Codable, Sendable {
    let type: String
    let toolUseId: String?
    let content: ToolResultContent?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}
