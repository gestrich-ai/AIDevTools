import Foundation

public struct RepositoryEvalConfig {
    public let casesDirectory: URL
    public let outputDirectory: URL
    public let repoRoot: URL

    public init(casesDirectory: URL, outputDirectory: URL, repoRoot: URL) {
        self.casesDirectory = casesDirectory
        self.outputDirectory = outputDirectory
        self.repoRoot = repoRoot
    }
}
