import AIOutputSDK
import Foundation

public struct ChatMessage: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let role: Role
    public let contentBlocks: [AIContentBlock]
    public let images: [ImageAttachment]
    public let timestamp: Date
    public let isComplete: Bool

    public enum Role: Sendable, Equatable {
        case assistant
        case user
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        images: [ImageAttachment] = [],
        timestamp: Date = Date(),
        isComplete: Bool = false
    ) {
        self.id = id
        self.role = role
        self.contentBlocks = content.isEmpty ? [] : [.text(content)]
        self.images = images
        self.timestamp = timestamp
        self.isComplete = isComplete
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        contentBlocks: [AIContentBlock],
        images: [ImageAttachment] = [],
        timestamp: Date = Date(),
        isComplete: Bool = false
    ) {
        self.id = id
        self.role = role
        self.contentBlocks = contentBlocks
        self.images = images
        self.timestamp = timestamp
        self.isComplete = isComplete
    }

    public var content: String {
        contentBlocks.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined()
    }

    public var shouldCollapseThinking: Bool {
        guard role == .assistant, isComplete else { return false }

        let hasThinkingOrTools = contentBlocks.contains { block in
            switch block {
            case .thinking, .toolUse, .toolResult: return true
            default: return false
            }
        }
        let hasText = contentBlocks.contains { block in
            if case .text = block { return true }
            return false
        }

        return hasThinkingOrTools && hasText
    }
}
