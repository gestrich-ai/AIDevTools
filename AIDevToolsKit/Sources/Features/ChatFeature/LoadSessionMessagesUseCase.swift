import AIOutputSDK
import Foundation
import UseCaseSDK

public struct LoadSessionMessagesUseCase: UseCase {

    public struct Options: Sendable {
        public let sessionId: String
        public let workingDirectory: String

        public init(sessionId: String, workingDirectory: String) {
            self.sessionId = sessionId
            self.workingDirectory = workingDirectory
        }
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(_ options: Options) async -> [ChatMessage] {
        let sessionMessages = await client.loadSessionMessages(sessionId: options.sessionId, workingDirectory: options.workingDirectory)
        return sessionMessages.map { msg in
            switch msg.role {
            case .user:
                return ChatMessage(role: .user, content: msg.content, isComplete: true)
            case .thinking:
                return ChatMessage(role: .assistant, contentBlocks: [.thinking(msg.content)], isComplete: true)
            case .assistant:
                return ChatMessage(role: .assistant, content: msg.content, isComplete: true)
            }
        }
    }
}
