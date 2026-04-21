import Foundation

public struct RepositoryConfiguration: Codable, Identifiable, Sendable {
    public let id: UUID
    public let path: URL
    public let name: String
    public var anthropicCredentialProfileId: String?
    public var architectureDocs: [String]?
    public var description: String?
    public var eval: EvalRepoSettings?
    public var githubCredentialProfileId: String?
    public var planner: PlanRepoSettings?
    public var prradar: PRRadarRepoSettings?
    public var pullRequest: PullRequestConfig?
    public var recentFocus: String?
    public var runCommands: [RepoRunCommand]?
    public var skills: [String]?
    public var verification: Verification?

    public init(
        id: UUID = UUID(),
        path: URL,
        name: String? = nil,
        anthropicCredentialProfileId: String? = nil,
        architectureDocs: [String]? = nil,
        description: String? = nil,
        eval: EvalRepoSettings? = nil,
        githubCredentialProfileId: String? = nil,
        planner: PlanRepoSettings? = nil,
        prradar: PRRadarRepoSettings? = nil,
        pullRequest: PullRequestConfig? = nil,
        recentFocus: String? = nil,
        runCommands: [RepoRunCommand]? = nil,
        skills: [String]? = nil,
        verification: Verification? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.anthropicCredentialProfileId = anthropicCredentialProfileId
        self.architectureDocs = architectureDocs
        self.description = description
        self.eval = eval
        self.githubCredentialProfileId = githubCredentialProfileId
        self.planner = planner
        self.prradar = prradar
        self.pullRequest = pullRequest
        self.recentFocus = recentFocus
        self.runCommands = runCommands
        self.skills = skills
        self.verification = verification
    }

    public func with(id: UUID) -> RepositoryConfiguration {
        RepositoryConfiguration(
            id: id,
            path: path,
            name: name,
            anthropicCredentialProfileId: anthropicCredentialProfileId,
            architectureDocs: architectureDocs,
            description: description,
            eval: eval,
            githubCredentialProfileId: githubCredentialProfileId,
            planner: planner,
            prradar: prradar,
            pullRequest: pullRequest,
            recentFocus: recentFocus,
            runCommands: runCommands,
            skills: skills,
            verification: verification
        )
    }
}

public struct RepoRunCommand: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var command: String
    public var isDefault: Bool
    public var name: String

    public init(id: UUID = UUID(), command: String, isDefault: Bool = false, name: String) {
        self.id = id
        self.command = command
        self.isDefault = isDefault
        self.name = name
    }
}

public struct Verification: Codable, Sendable, Equatable {
    public let commands: [String]
    public let notes: String?

    public init(commands: [String], notes: String? = nil) {
        self.commands = commands
        self.notes = notes
    }
}

public struct PullRequestConfig: Codable, Sendable, Equatable {
    public static let defaultBaseBranch = "main"
    public static let defaultBranchNamingConvention = "feature/description"

    public let baseBranch: String
    public let branchNamingConvention: String
    public let template: String?
    public let notes: String?

    public init(
        baseBranch: String,
        branchNamingConvention: String,
        template: String? = nil,
        notes: String? = nil
    ) {
        self.baseBranch = baseBranch
        self.branchNamingConvention = branchNamingConvention
        self.template = template
        self.notes = notes
    }

    /// Creates a config from raw form strings. Returns nil if all fields are empty.
    public static func from(
        baseBranch: String,
        branchNamingConvention: String,
        template: String,
        notes: String
    ) -> PullRequestConfig? {
        guard !baseBranch.isEmpty || !branchNamingConvention.isEmpty
            || !template.isEmpty || !notes.isEmpty else {
            return nil
        }
        return PullRequestConfig(
            baseBranch: baseBranch,
            branchNamingConvention: branchNamingConvention,
            template: template.isEmpty ? nil : template,
            notes: notes.isEmpty ? nil : notes
        )
    }
}
