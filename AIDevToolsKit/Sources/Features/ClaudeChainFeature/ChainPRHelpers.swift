import Foundation
import GitSDK

struct ChainPRHelpers {

    static func buildPRTitle(projectName: String, task: String) -> String {
        let maxTitleLength = 80
        let titlePrefix = "ClaudeChain: [\(projectName)] "
        let availableForTask = maxTitleLength - titlePrefix.count
        let truncatedTask = task.count > availableForTask
            ? String(task.prefix(availableForTask - 3)) + "..."
            : task
        return "\(titlePrefix)\(truncatedTask)"
    }

    static func extractCost() -> Double {
        // Cost is typically reported in stderr as part of Claude CLI output
        // For now, return 0.0 — the cost will be populated when metrics events are available
        return 0.0
    }

    static func parsePRNumber(from jsonOutput: String) -> String? {
        guard let data = jsonOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = json["number"] as? Int else {
            return nil
        }
        return String(number)
    }

    static func detectRepo(workingDirectory: String, git: GitClient) async -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        guard let remoteURL = try? await git.remoteGetURL(workingDirectory: workingDirectory),
              remoteURL.contains("github.com") else {
            return ""
        }
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
    }
}
