import Foundation

public struct GitCommit: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let hash: String
    public let shortHash: String
    public let message: String
    public let author: String
    public let date: Date

    public init(hash: String, shortHash: String, message: String, author: String, date: Date) {
        self.id = hash
        self.hash = hash
        self.shortHash = shortHash
        self.message = message
        self.author = author
        self.date = date
    }
}

public enum RebaseAction: String, Sendable, Codable, CaseIterable, Equatable {
    case pick
    case squash
    case edit
    case drop
    case reword

    public var displayName: String {
        switch self {
        case .pick: return "Pick"
        case .squash: return "Squash"
        case .edit: return "Edit"
        case .drop: return "Drop"
        case .reword: return "Reword"
        }
    }
}

public struct RebaseCommitEntry: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let commit: GitCommit
    public var action: RebaseAction
    public var editedMessage: String?

    public init(commit: GitCommit, action: RebaseAction = .pick, editedMessage: String? = nil) {
        self.id = commit.id
        self.commit = commit
        self.action = action
        self.editedMessage = editedMessage
    }
}

public enum RebaseStatus: Sendable, Equatable {
    case idle
    case inProgress
    case success
    case conflict(message: String)
    case error(message: String)
}
