import AIOutputSDK
import Foundation
import UseCaseSDK

public struct ResumeLatestSessionUseCase: UseCase {

    public struct Options: Sendable {
        public let workingDirectory: String

        public init(workingDirectory: String) {
            self.workingDirectory = workingDirectory
        }
    }

    public struct Result: Sendable {
        public let messages: [ChatMessage]
        public let sessionId: String

        public init(messages: [ChatMessage], sessionId: String) {
            self.messages = messages
            self.sessionId = sessionId
        }
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(_ options: Options) async -> Result? {
        let sessions = await client.listSessions(workingDirectory: options.workingDirectory)
        guard let mostRecent = sessions.first else { return nil }
        let sessionMessages = await client.loadSessionMessages(sessionId: mostRecent.id, workingDirectory: options.workingDirectory)
        let messages = sessionMessages.map { ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.content, isComplete: true) }
        return Result(messages: messages, sessionId: mostRecent.id)
    }
}
