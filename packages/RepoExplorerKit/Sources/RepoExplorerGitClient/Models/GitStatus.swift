import Foundation

/// Represents the current state of a git repository
public struct GitRepositoryStatus: Sendable, Equatable {
    /// Current branch name (empty if detached HEAD)
    public let branch: String?

    /// Short SHA if in detached HEAD state
    public let detachedHead: String?

    /// Rebase state if currently rebasing
    public let rebaseState: RebaseState?

    /// Files with changes
    public let files: [GitFileStatus]

    /// Whether there are any uncommitted changes
    public var hasUncommittedChanges: Bool {
        !files.isEmpty
    }

    /// Whether repository is in detached HEAD state
    public var isDetached: Bool {
        branch == nil && detachedHead != nil
    }

    /// Whether repository is currently in a rebase
    public var isRebasing: Bool {
        rebaseState != nil
    }

    public init(
        branch: String?,
        detachedHead: String?,
        rebaseState: RebaseState?,
        files: [GitFileStatus]
    ) {
        self.branch = branch
        self.detachedHead = detachedHead
        self.rebaseState = rebaseState
        self.files = files
    }
}

/// State of an active rebase operation
public struct RebaseState: Sendable, Equatable {
    /// Branch being rebased
    public let branchName: String

    /// Commit being rebased onto
    public let ontoCommit: String

    /// Current step number
    public let currentStep: Int

    /// Total number of steps
    public let totalSteps: Int

    /// Files with merge conflicts
    public let conflicts: [String]

    /// Whether there are conflicts to resolve
    public var hasConflicts: Bool {
        !conflicts.isEmpty
    }

    /// Progress as percentage (0.0 to 1.0)
    public var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }

    public init(
        branchName: String,
        ontoCommit: String,
        currentStep: Int,
        totalSteps: Int,
        conflicts: [String]
    ) {
        self.branchName = branchName
        self.ontoCommit = ontoCommit
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.conflicts = conflicts
    }
}

/// Status of a single file in the working tree
public struct GitFileStatus: Sendable, Equatable {
    /// File path relative to repository root
    public let path: String

    /// Status in the index (staging area)
    public let indexStatus: FileStatusCode

    /// Status in the working tree
    public let workingTreeStatus: FileStatusCode

    /// Whether file is staged
    public var isStaged: Bool {
        indexStatus != .unmodified && indexStatus != .untracked
    }

    /// Whether file has unstaged changes
    public var hasUnstagedChanges: Bool {
        workingTreeStatus != .unmodified && workingTreeStatus != .untracked
    }

    /// Whether file has merge conflicts
    public var hasConflict: Bool {
        indexStatus == .bothModified ||
        indexStatus == .bothAdded ||
        indexStatus == .bothDeleted
    }

    public init(path: String, indexStatus: FileStatusCode, workingTreeStatus: FileStatusCode) {
        self.path = path
        self.indexStatus = indexStatus
        self.workingTreeStatus = workingTreeStatus
    }
}

/// Git file status codes from porcelain format
public enum FileStatusCode: String, Sendable, Equatable {
    case unmodified = " "
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "!"
    case bothModified = "U"  // Merge conflict: both modified
    case bothAdded = "AA"     // Merge conflict: both added
    case bothDeleted = "DD"   // Merge conflict: both deleted

    public var displayName: String {
        switch self {
        case .unmodified: return "Unmodified"
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .untracked: return "Untracked"
        case .ignored: return "Ignored"
        case .bothModified: return "Conflict (Both Modified)"
        case .bothAdded: return "Conflict (Both Added)"
        case .bothDeleted: return "Conflict (Both Deleted)"
        }
    }
}
