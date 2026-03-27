import Foundation

enum CodexEventItemType {
    static let commandExecution = "command_execution"
}

enum CodexStreamEventType {
    static let itemCompleted = "item.completed"
}

struct CodexStreamEvent: Codable, Sendable {
    let type: String?
    let item: CodexEventItem?
}

struct CodexEventItem: Codable, Sendable {
    let type: String
    let command: String?
    let aggregatedOutput: String?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case type, command
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
    }
}
