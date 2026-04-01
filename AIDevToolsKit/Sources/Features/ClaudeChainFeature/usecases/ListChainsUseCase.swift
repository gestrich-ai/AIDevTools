import ClaudeChainSDK
import ClaudeChainService
import Foundation
import UseCaseSDK

public struct ListChainsUseCase: UseCase {

    public struct Options: Sendable {
        public let repoPath: URL

        public init(repoPath: URL) {
            self.repoPath = repoPath
        }
    }

    public init() {}

    public func run(options: Options) throws -> [ChainProject] {
        let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
        let projects = Project.findAll(baseDir: chainDir)

        return projects.compactMap { project in
            let absoluteProject = Project(
                name: project.name,
                basePath: (chainDir as NSString).appendingPathComponent(project.name)
            )
            let githubClient = GitHubClient(workingDirectory: chainDir)
            let repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))
            guard let spec = try? repository.loadLocalSpec(project: absoluteProject) else {
                return nil
            }
            let config = (try? repository.loadLocalConfiguration(project: absoluteProject))
                ?? ProjectConfiguration.default(project: absoluteProject)
            let baseBranch = config.getBaseBranch(defaultBaseBranch: Constants.defaultBaseBranch)
            let tasks = spec.tasks.map { specTask in
                ChainTask(
                    index: specTask.index,
                    description: specTask.description,
                    isCompleted: specTask.isCompleted
                )
            }
            return ChainProject(
                name: project.name,
                specPath: absoluteProject.specPath,
                tasks: tasks,
                completedTasks: spec.completedTasks,
                pendingTasks: spec.pendingTasks,
                totalTasks: spec.totalTasks,
                baseBranch: baseBranch
            )
        }
    }
}
