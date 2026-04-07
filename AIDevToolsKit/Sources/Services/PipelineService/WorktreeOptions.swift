public struct WorktreeOptions: Sendable {
    public let branchName: String
    public let destinationPath: String
    public let repoPath: String

    public init(branchName: String, destinationPath: String, repoPath: String) {
        self.branchName = branchName
        self.destinationPath = destinationPath
        self.repoPath = repoPath
    }
}
