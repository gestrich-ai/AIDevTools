public struct WorktreeOptions: Sendable {
    public let basedOn: String?
    public let branchName: String
    public let destinationPath: String
    public let repoPath: String

    public init(branchName: String, destinationPath: String, repoPath: String, basedOn: String? = nil) {
        self.basedOn = basedOn
        self.branchName = branchName
        self.destinationPath = destinationPath
        self.repoPath = repoPath
    }
}
