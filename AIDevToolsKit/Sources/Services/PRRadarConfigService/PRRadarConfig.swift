import EnvironmentSDK
import Foundation
import PRRadarModelsService
import RepositorySDK

public struct RepositoryConfiguration: Sendable {
    public let id: UUID
    public let name: String
    public let repoPath: String
    public let outputDir: String
    public let rulePaths: [RulePath]
    public let agentScriptPath: String
    public let githubAccount: String
    public let diffSource: DiffSource
    public let defaultBaseBranch: String

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        outputDir: String,
        rulePaths: [RulePath] = [],
        agentScriptPath: String,
        githubAccount: String,
        diffSource: DiffSource = .git,
        defaultBaseBranch: String
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.rulePaths = rulePaths
        self.agentScriptPath = agentScriptPath
        self.githubAccount = githubAccount
        self.diffSource = diffSource
        self.defaultBaseBranch = defaultBaseBranch
    }

    public static func make(
        from info: RepositoryInfo,
        settings: PRRadarRepoSettings,
        outputDir: String,
        agentScriptPath: String
    ) -> RepositoryConfiguration {
        RepositoryConfiguration(
            id: info.id,
            name: info.name,
            repoPath: info.path.path(percentEncoded: false),
            outputDir: outputDir,
            rulePaths: settings.rulePaths,
            agentScriptPath: agentScriptPath,
            githubAccount: info.credentialAccount ?? "",
            diffSource: settings.diffSource,
            defaultBaseBranch: info.pullRequest?.baseBranch ?? "main"
        )
    }

    public static var defaultRulePaths: [RulePath] {
        [RulePath(name: "default", path: "code-review-rules", isDefault: true)]
    }

    public var defaultRulePath: RulePath? {
        rulePaths.first(where: { $0.isDefault }) ?? rulePaths.first
    }

    public var resolvedDefaultRulesDir: String {
        guard let defaultPath = defaultRulePath else { return "" }
        return resolvedRulesDir(for: defaultPath)
    }

    public var allResolvedRulesDirs: [String] {
        rulePaths.map { resolvedRulesDir(for: $0) }
    }

    public func resolvedRulesDir(for rulePath: RulePath) -> String {
        PathUtilities.resolve(rulePath.path, relativeTo: repoPath)
    }

    public func resolvedRulesDir(named name: String) -> String? {
        guard let rulePath = rulePaths.first(where: { $0.name == name }) else {
            return nil
        }
        return resolvedRulesDir(for: rulePath)
    }

    public var resolvedOutputDir: String {
        PathUtilities.resolve(outputDir, relativeTo: repoPath)
    }

    public func prDataDirectory(for prNumber: Int) -> String {
        "\(resolvedOutputDir)/\(prNumber)"
    }

    public func makeFilter(
        dateFilter: PRDateFilter? = nil,
        state: PRState? = nil,
        baseBranch: String? = nil,
        authorLogin: String? = nil
    ) -> PRFilter {
        let resolvedBase: String?
        if let baseBranch {
            resolvedBase = (baseBranch.lowercased() == "all" || baseBranch.isEmpty) ? nil : baseBranch
        } else {
            resolvedBase = defaultBaseBranch
        }
        return PRFilter(
            dateFilter: dateFilter,
            state: state ?? .open,
            baseBranch: resolvedBase,
            authorLogin: authorLogin
        )
    }
}
