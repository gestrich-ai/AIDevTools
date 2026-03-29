import Foundation

public struct PRRadarRepoSettings: Codable, Sendable {
    public let repoId: UUID
    public var rulePaths: [RulePath]
    public var diffSource: DiffSource

    public init(repoId: UUID, rulePaths: [RulePath] = [], diffSource: DiffSource = .git) {
        self.repoId = repoId
        self.rulePaths = rulePaths
        self.diffSource = diffSource
    }
}
