import Foundation

/// Discovers `ClaudeChainSource` instances from a repository.
public protocol ChainDiscoveryService: Sendable {
    func discoverSources(repoPath: URL) throws -> [any ClaudeChainSource]
}

/// Scans the local filesystem for plan (`claude-chain/`) and sweep
/// (`claude-chain-sweep/`) chain directories.
public struct LocalChainDiscoveryService: ChainDiscoveryService {

    public init() {}

    public func discoverSources(repoPath: URL) throws -> [any ClaudeChainSource] {
        var sources: [any ClaudeChainSource] = []
        sources += discoverPlanSources(repoPath: repoPath)
        sources += try discoverSweepSources(repoPath: repoPath)
        return sources
    }

    // MARK: - Private

    private func discoverPlanSources(repoPath: URL) -> [any ClaudeChainSource] {
        let chainDir = repoPath.appendingPathComponent(ClaudeChainConstants.projectDirectoryPrefix)
        guard FileManager.default.fileExists(atPath: chainDir.path),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: chainDir.path) else { return [] }
        return entries.sorted().compactMap { entry -> (any ClaudeChainSource)? in
            let taskDir = chainDir.appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: taskDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.fileExists(atPath: taskDir.appendingPathComponent(ClaudeChainConstants.specFileName).path)
            else { return nil }
            return MarkdownClaudeChainSource(projectName: entry, repoPath: repoPath)
        }
    }

    private func discoverSweepSources(repoPath: URL) throws -> [any ClaudeChainSource] {
        let sweepDir = repoPath.appendingPathComponent(ClaudeChainConstants.sweepChainDirectory)
        guard FileManager.default.fileExists(atPath: sweepDir.path) else { return [] }

        let entries = try FileManager.default.contentsOfDirectory(atPath: sweepDir.path)
        return entries.sorted().compactMap { entry -> (any ClaudeChainSource)? in
            let taskDir = sweepDir.appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: taskDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.fileExists(atPath: taskDir.appendingPathComponent(ClaudeChainConstants.specFileName).path)
            else { return nil }
            return SweepClaudeChainSource(taskName: entry, taskDirectory: taskDir, repoPath: repoPath)
        }
    }
}
