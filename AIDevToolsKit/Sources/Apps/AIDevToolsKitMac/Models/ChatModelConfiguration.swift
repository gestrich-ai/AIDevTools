import AIOutputSDK
import Foundation

public struct ChatModelConfiguration {
    public let client: any AIClient
    public let mcpConfigPath: String?
    public let settings: ChatSettings
    public let systemPrompt: String?
    public let workingDirectory: String?

    public init(
        client: any AIClient,
        mcpConfigPath: String? = nil,
        settings: ChatSettings = ChatSettings(),
        systemPrompt: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.client = client
        self.mcpConfigPath = mcpConfigPath
        self.settings = settings
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
    }
}
