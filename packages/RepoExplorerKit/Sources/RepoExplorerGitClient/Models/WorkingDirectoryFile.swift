import Foundation

/// Filter for working directory files
public enum WorkingDirectoryFilter: Sendable, Equatable {
    case all        // Show all files
    case staged     // Show only files with staged changes
    case unstaged   // Show only files with unstaged changes
}

/// Represents a file in the working directory with its git status
/// This merges both staged and unstaged status for files that have dual status (e.g., AD)
public struct WorkingDirectoryFile: Identifiable, Sendable, Equatable {
    public let filePath: String
    public let stagedStatus: GitCommandBuilder.FileChangeStatus?      // Status in staging area (index)
    public let unstagedStatus: GitCommandBuilder.FileChangeStatus?    // Status in working tree
    public let renamedFrom: String?

    public init(
        filePath: String,
        stagedStatus: GitCommandBuilder.FileChangeStatus?,
        unstagedStatus: GitCommandBuilder.FileChangeStatus?,
        renamedFrom: String? = nil
    ) {
        self.filePath = filePath
        self.stagedStatus = stagedStatus
        self.unstagedStatus = unstagedStatus
        self.renamedFrom = renamedFrom
    }

    public var id: String { filePath }

    /// Whether this file has any staged changes
    public var isStaged: Bool {
        stagedStatus != nil
    }

    /// Whether this file has any unstaged changes
    public var hasUnstagedChanges: Bool {
        unstagedStatus != nil
    }

    /// Primary status to display (prefer staged if both exist)
    public var primaryStatus: GitCommandBuilder.FileChangeStatus {
        stagedStatus ?? unstagedStatus ?? .modified
    }

    /// All status codes for this file (for displaying multiple badges)
    public var allStatuses: [GitCommandBuilder.FileChangeStatus] {
        var statuses: [GitCommandBuilder.FileChangeStatus] = []
        if let staged = stagedStatus {
            statuses.append(staged)
        }
        if let unstaged = unstagedStatus {
            statuses.append(unstaged)
        }
        return statuses
    }
}
