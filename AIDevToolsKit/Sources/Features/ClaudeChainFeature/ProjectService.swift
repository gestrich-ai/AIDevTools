import ClaudeChainService
import Foundation

public struct ProjectService {

    public static func detectProjectsFromMerge(changedFiles: [String]) -> [Project] {
        var projects = Set<Project>()
        for filePath in changedFiles {
            if let name = MarkdownClaudeChainSource.matchesSpecPath(filePath) {
                projects.insert(Project(name: name, basePath: "\(ClaudeChainConstants.projectDirectoryPrefix)/\(name)"))
            } else if let name = SweepClaudeChainSource.matchesSpecPath(filePath) {
                projects.insert(Project(name: name, basePath: "\(ClaudeChainConstants.sweepChainDirectory)/\(name)"))
            }
        }
        return projects.sorted { $0.name < $1.name }
    }
}