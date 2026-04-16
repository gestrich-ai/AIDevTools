import AIOutputSDK
import Foundation

public struct MCPService: Sendable {
    private let configurableProviders: [any MCPConfigurable]

    public init(configurableProviders: [any MCPConfigurable] = []) {
        self.configurableProviders = configurableProviders
    }

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
        for provider in configurableProviders {
            provider.writeMCPConfig(binaryURL: binaryURL)
        }
    }
}
