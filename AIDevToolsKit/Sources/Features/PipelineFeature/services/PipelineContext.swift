import Foundation

public struct PipelineContext: Sendable {
    public let repoPath: URL?
    public let workingDirectory: String?
    public var gitBranch: String?
    public var accumulatedLogs: String

    public init(
        repoPath: URL? = nil,
        workingDirectory: String? = nil,
        gitBranch: String? = nil,
        accumulatedLogs: String = ""
    ) {
        self.repoPath = repoPath
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.accumulatedLogs = accumulatedLogs
    }
}
