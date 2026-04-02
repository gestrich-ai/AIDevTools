import Foundation

public struct StepExecutionContext: Sendable {
    public let repoPath: URL
    public let workingDirectory: String
    public var gitBranch: String?
    public var accumulatedLogs: String

    public init(
        repoPath: URL,
        workingDirectory: String,
        gitBranch: String?,
        accumulatedLogs: String
    ) {
        self.repoPath = repoPath
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.accumulatedLogs = accumulatedLogs
    }
}
