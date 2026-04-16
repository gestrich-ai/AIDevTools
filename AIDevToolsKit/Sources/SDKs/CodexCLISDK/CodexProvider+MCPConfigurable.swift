import AIOutputSDK
import Foundation

extension CodexProvider: MCPConfigurable {
    public func writeMCPConfig(binaryURL: URL) {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")

        var lines = (try? String(contentsOf: configURL, encoding: .utf8))?
            .components(separatedBy: "\n") ?? []

        if let sectionIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "[mcp_servers.ai-dev-tools-kit]"
        }) {
            let sectionEnd = lines[(sectionIndex + 1)...]
                .firstIndex(where: { $0.hasPrefix("[") }) ?? lines.endIndex
            lines.removeSubrange(sectionIndex..<sectionEnd)
        }

        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }

        if !lines.isEmpty {
            lines.append("")
        }
        lines.append("[mcp_servers.ai-dev-tools-kit]")
        lines.append("command = \"\(binaryURL.path)\"")
        lines.append("args = [\"mcp\"]")

        let content = lines.joined(separator: "\n")
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }
}
