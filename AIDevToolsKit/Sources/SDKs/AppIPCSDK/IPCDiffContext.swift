import Foundation

public struct IPCDiffContext: Codable, Equatable, Sendable {
    public let selectedCommits: [IPCDiffCommit]
    public let selectedFilePath: String?
    public let selectedSources: [String]

    public init(selectedCommits: [IPCDiffCommit], selectedFilePath: String?, selectedSources: [String]) {
        self.selectedCommits = selectedCommits
        self.selectedFilePath = selectedFilePath
        self.selectedSources = selectedSources
    }
}
