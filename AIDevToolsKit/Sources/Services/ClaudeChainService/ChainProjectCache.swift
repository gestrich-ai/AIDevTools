import Foundation

public struct ChainProjectCache: Sendable {
    private let projectDirectory: URL

    public struct Descriptor: Codable, Sendable {
        public let commitHash: String

        public init(commitHash: String) {
            self.commitHash = commitHash
        }
    }

    public init(projectDirectory: URL) {
        self.projectDirectory = projectDirectory
    }

    /// Returns the parsed descriptor, or nil if the file is absent or cannot be decoded.
    public func readDescriptor() throws -> Descriptor? {
        let url = descriptorURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        // Swallowing intentionally: malformed JSON is treated as absent — forces re-download on next refresh.
        return try? JSONDecoder().decode(Descriptor.self, from: data)
    }

    /// Atomically writes the descriptor to project-cache.json.
    public func writeDescriptor(_ descriptor: Descriptor) throws {
        let data = try JSONEncoder().encode(descriptor)
        try data.write(to: descriptorURL(), options: .atomic)
    }

    /// Returns the file content at the given repo-relative path, or nil if absent.
    /// Example: readFile(at: "claude-chain/my-project/spec.md")
    public func readFile(at repoRelativePath: String) throws -> String? {
        let url = fileCacheURL(for: repoRelativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Writes content to file-cache/<repoRelativePath>, creating intermediate directories.
    public func writeFile(_ content: String, at repoRelativePath: String) throws {
        let url = fileCacheURL(for: repoRelativePath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func descriptorURL() -> URL {
        projectDirectory.appendingPathComponent("project-cache.json")
    }

    private func fileCacheURL(for repoRelativePath: String) -> URL {
        projectDirectory.appendingPathComponent("file-cache").appendingPathComponent(repoRelativePath)
    }
}
