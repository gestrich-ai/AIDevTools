import ClaudeCodeChatService
import Foundation

public struct ListClaudeCodeSessionsUseCase: Sendable {

    public struct Options: Sendable {
        public let workingDirectory: String

        public init(workingDirectory: String) {
            self.workingDirectory = workingDirectory
        }
    }

    public init() {}

    public func run(_ options: Options) async -> [ClaudeSession] {
        await ClaudeCodeChatManager.listSessionsFromDisk(workingDirectory: options.workingDirectory)
    }
}
