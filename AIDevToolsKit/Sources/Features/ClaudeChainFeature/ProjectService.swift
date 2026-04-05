import ClaudeChainService
import Foundation

public struct ProjectService {

    private static let specRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^claude-chain/([^/]+)/spec\.md$"#, options: [])
        } catch {
            fatalError("Invalid regex pattern: \(error)")
        }
    }()

    public static func detectProjectsFromMerge(changedFiles: [String]) -> [Project] {
        var projectNames = Set<String>()
        for filePath in changedFiles {
            let range = NSRange(location: 0, length: filePath.utf16.count)
            if let match = specRegex.firstMatch(in: filePath, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: filePath) {
                projectNames.insert(String(filePath[captureRange]))
            }
        }
        return projectNames.sorted().map { Project(name: $0, basePath: "\(ClaudeChainConstants.projectDirectoryPrefix)/\($0)") }
    }
}