/**
 * Core service for project detection operations.
 *
 * Follows Service Layer pattern (Fowler, PoEAA) - encapsulates business logic
 * for detecting projects from changed files.
 */

import ClaudeChainService
import Foundation

public class ProjectService {
    /**
     * Core service for project detection operations.
     *
     * Provides static methods for identifying ClaudeChain projects from file changes.
     */
    
    public static func detectProjectsFromMerge(changedFiles: [String]) -> [Project] {
        /**
         * Detect projects from changed spec.md files in a merge.
         *
         * This function is used to automatically trigger ClaudeChain when spec files
         * are changed, regardless of branch naming conventions or labels. It enables
         * the "changed files" triggering model where:
         * - Initial spec merge: User creates PR with spec.md, merges it, workflow triggers
         * - Subsequent merges: System-created PRs merge, workflow triggers same way
         *
         * Args:
         *     changedFiles: List of file paths that changed in the merge
         *
         * Returns:
         *     List of Project objects for projects with changed spec.md files.
         *     Empty list if no spec files were changed.
         *
         * Examples:
         *     files = ["claude-chain/my-project/spec.md", "README.md"]
         *     projects = ProjectService.detectProjectsFromMerge(changedFiles: files)
         *     projects.map { $0.name }  // ['my-project']
         *
         *     files = ["claude-chain/project-a/spec.md", "claude-chain/project-b/spec.md"]
         *     projects = ProjectService.detectProjectsFromMerge(changedFiles: files)
         *     projects.map { $0.name }.sorted()  // ['project-a', 'project-b']
         *
         *     files = ["src/main.py", "README.md"]
         *     ProjectService.detectProjectsFromMerge(changedFiles: files)  // []
         */
        let specPattern = #"^claude-chain/([^/]+)/spec\.md$"#
        let regex = try! NSRegularExpression(pattern: specPattern, options: [])
        var projectNames = Set<String>()
        
        for filePath in changedFiles {
            let range = NSRange(location: 0, length: filePath.utf16.count)
            if let match = regex.firstMatch(in: filePath, options: [], range: range) {
                let projectName = String(filePath[Range(match.range(at: 1), in: filePath)!])
                projectNames.insert(projectName)
            }
        }
        
        return projectNames.sorted().map { Project(name: $0) }
    }
}