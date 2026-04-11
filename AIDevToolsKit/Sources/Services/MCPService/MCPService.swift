import DataPathsService
import Foundation

public struct MCPService: Sendable {

    public init() {}

    public static func siblingBinaryURL(bundleURL: URL) -> URL {
        bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ai-dev-tools-kit")
    }

    public static func swiftBuildBinaryURL(repoPath: URL) -> URL {
        repoPath
            .appendingPathComponent("AIDevToolsKit")
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("ai-dev-tools-kit")
    }

    public func resolveStatus(bundleURL: URL, repoPath: URL?) -> MCPStatus {
        let fm = FileManager.default
        let siblingURL = Self.siblingBinaryURL(bundleURL: bundleURL)

        var candidates: [URL] = []
        if fm.fileExists(atPath: siblingURL.path) {
            candidates.append(siblingURL)
        }
        if let repoPath {
            let swiftBuildURL = Self.swiftBuildBinaryURL(repoPath: repoPath)
            if fm.fileExists(atPath: swiftBuildURL.path) {
                candidates.append(swiftBuildURL)
            }
        }

        if candidates.isEmpty {
            return repoPath == nil ? .notConfigured : .binaryMissing
        }

        guard let mostRecent = candidates.max(by: { a, b in
            // File attribute errors are acceptable; treat unreadable dates as oldest.
            let aDate = (try? fm.attributesOfItem(atPath: a.path)[.modificationDate] as? Date) ?? .distantPast
            let bDate = (try? fm.attributesOfItem(atPath: b.path)[.modificationDate] as? Date) ?? .distantPast
            return aDate < bDate
        }) else { return .binaryMissing }

        let builtAt = (try? fm.attributesOfItem(atPath: mostRecent.path)[.modificationDate] as? Date) ?? .distantPast
        return .ready(binaryURL: mostRecent, builtAt: builtAt)
    }

    public func writeMCPConfigFromCurrentProcess() {
        let arg0 = ProcessInfo.processInfo.arguments[0]
        let executableURL: URL
        if arg0.hasPrefix("/") {
            executableURL = URL(fileURLWithPath: arg0).standardizedFileURL
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            executableURL = URL(fileURLWithPath: arg0, relativeTo: cwd).standardizedFileURL
        }
        writeMCPConfig(binaryURL: executableURL)
    }

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
        let fileURL = DataPathsService.mcpConfigFileURL
        // Best-effort write; failure here is non-fatal.
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? config.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
