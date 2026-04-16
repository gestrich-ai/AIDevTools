import Foundation

/// How ownership was determined
public enum AttributionMethod: String, Codable, Sendable {
    case gitBlame = "git_blame"
    case lastCommit = "last_commit"
    case testHeuristics = "test_heuristics"
    case filePattern = "file_pattern"
    case manual = "manual"
}
