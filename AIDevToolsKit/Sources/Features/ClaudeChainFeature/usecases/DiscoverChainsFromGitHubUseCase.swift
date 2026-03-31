import ClaudeChainService
import Foundation
import UseCaseSDK

public struct DiscoveredChain: Sendable {
    public let baseRefName: String
    public let openPRCount: Int
    public let projectName: String

    public init(baseRefName: String, openPRCount: Int, projectName: String) {
        self.baseRefName = baseRefName
        self.openPRCount = openPRCount
        self.projectName = projectName
    }
}

public struct DiscoverChainsFromGitHubUseCase: UseCase {

    public struct Options: Sendable {
        public let label: String
        public let repo: String

        public init(repo: String, label: String = Constants.defaultPRLabel) {
            self.label = label
            self.repo = repo
        }
    }

    public init() {}

    public func run(options: Options) throws -> [DiscoveredChain] {
        let openPRs = try GitHubOperations.listPullRequests(
            repo: options.repo,
            state: "open",
            label: options.label,
            limit: 500
        )

        var countsByProject: [String: Int] = [:]
        var baseRefByProject: [String: String] = [:]

        for pr in openPRs {
            guard let headRefName = pr.headRefName,
                  let baseRefName = pr.baseRefName,
                  let branchInfo = BranchInfo.fromBranchName(headRefName) else {
                continue
            }
            let project = branchInfo.projectName
            countsByProject[project, default: 0] += 1
            if baseRefByProject[project] == nil {
                baseRefByProject[project] = baseRefName
            }
        }

        return countsByProject.map { projectName, count in
            DiscoveredChain(
                baseRefName: baseRefByProject[projectName] ?? "",
                openPRCount: count,
                projectName: projectName
            )
        }
    }
}
