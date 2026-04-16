import AIOutputSDK
import Foundation

extension ClaudeProvider: MCPConfigurable {
    public func writeMCPConfig(binaryURL: URL) {
        let config = """
        {
          "mcpServers": {
            "ai-dev-tools-kit": {
              "command": "\(binaryURL.path)",
              "args": ["mcp"]
            }
          }
        }
        """
        let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIDevTools/mcp-config.json")
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? config.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
