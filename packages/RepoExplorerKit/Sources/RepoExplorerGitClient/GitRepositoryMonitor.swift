import RepoExplorerCLITools
import Foundation

/// Monitors Git repository changes by polling `git status` and comparing results.
/// This is fast even for huge repositories since Git efficiently tracks changes.
public final class GitRepositoryMonitor: @unchecked Sendable {
    private var pollingTask: Task<Void, Never>?
    private var lastStatus: GitRepositoryStatus?
    private var lastDiffHash: String?
    private let repoPath: String
    private let pollInterval: TimeInterval
    private let onChange: @Sendable () async -> Void
    private let debouncer: ChangeDebouncer

    public init(
        repoPath: String,
        pollInterval: TimeInterval = 2.0,
        onChange: @escaping @Sendable () async -> Void
    ) {
        self.repoPath = repoPath
        self.pollInterval = pollInterval
        self.onChange = onChange
        self.debouncer = ChangeDebouncer()
    }

    /// Start monitoring Git repository changes
    public func startMonitoring() {
        stopMonitoring()

        print("🔍 GitRepositoryMonitor: Starting git status polling (every \(pollInterval)s) for \(repoPath)")

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await captureCurrentStatus()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard !Task.isCancelled else { break }
                await self.checkForChanges()
            }
        }
    }

    private func captureCurrentStatus() async {
        let gitBuilder = CommandBuilder().git()

        do {
            let status = try await gitBuilder.getRepositoryStatus(in: repoPath)
            lastStatus = status

            // Also capture diff hash
            let diffResult = try await gitBuilder.diffUnstaged(in: repoPath)
            lastDiffHash = String(diffResult.stdout.hashValue)

            print("🔍 GitRepositoryMonitor: Initial status captured (\(status.files.count) files with changes)")
        } catch {
            print("⚠️ GitRepositoryMonitor: Failed to get initial status: \(error)")
        }
    }

    private func checkForChanges() async {
        let gitBuilder = CommandBuilder().git()

        do {
            let currentStatus = try await gitBuilder.getRepositoryStatus(in: repoPath)

            // Get current diff hash (actual content)
            let diffResult = try await gitBuilder.diffUnstaged(in: repoPath)
            let currentDiffHash = String(diffResult.stdout.hashValue)

            // Compare with last status and diff
            guard let previousStatus = lastStatus, let previousDiffHash = lastDiffHash else {
                // First check - just store it
                lastStatus = currentStatus
                lastDiffHash = currentDiffHash
                return
            }

            // Check if status OR diff content changed
            let statusChanged = currentStatus != previousStatus
            let diffChanged = currentDiffHash != previousDiffHash

            if statusChanged || diffChanged {
                if statusChanged {
                    reportChanges(from: previousStatus, to: currentStatus)
                } else {
                    // Same files, but content changed
                    print("📝 GitRepositoryMonitor: File content modified (same files, different diffs)")
                }

                // Update cached values
                lastStatus = currentStatus
                lastDiffHash = currentDiffHash

                // Trigger refresh
                let onChange = self.onChange
                await debouncer.debounce {
                    print("🔄 GitRepositoryMonitor: Triggering refresh")
                    await onChange()
                }
            }
        } catch {
            print("⚠️ GitRepositoryMonitor: Failed to check status: \(error)")
        }
    }

    private func reportChanges(from old: GitRepositoryStatus, to new: GitRepositoryStatus) {
        // Branch changes
        if old.branch != new.branch || old.detachedHead != new.detachedHead {
            if let newBranch = new.branch {
                print("📝 GitRepositoryMonitor: Branch changed to \(newBranch)")
            } else if let newHead = new.detachedHead {
                print("📝 GitRepositoryMonitor: Now in detached HEAD: \(newHead)")
            }
        }

        // Rebase state changes
        if old.rebaseState != new.rebaseState {
            if let rebaseState = new.rebaseState {
                print("📝 GitRepositoryMonitor: Rebase started: \(rebaseState.branchName)")
            } else if old.rebaseState != nil {
                print("📝 GitRepositoryMonitor: Rebase ended")
            }
        }

        // File changes
        let oldFiles = Set(old.files.map(\.path))
        let newFiles = Set(new.files.map(\.path))

        let added = newFiles.subtracting(oldFiles)
        let removed = oldFiles.subtracting(newFiles)
        let modified = oldFiles.intersection(newFiles).filter { path in
            let oldFile = old.files.first { $0.path == path }
            let newFile = new.files.first { $0.path == path }
            return oldFile != newFile
        }

        if !added.isEmpty {
            let fileNames = added.prefix(5).map { ($0 as NSString).lastPathComponent }
            print("📝 GitRepositoryMonitor: Added: \(fileNames.joined(separator: ", "))\(added.count > 5 ? " (+ \(added.count - 5) more)" : "")")
        }
        if !removed.isEmpty {
            let fileNames = removed.prefix(5).map { ($0 as NSString).lastPathComponent }
            print("📝 GitRepositoryMonitor: Removed: \(fileNames.joined(separator: ", "))\(removed.count > 5 ? " (+ \(removed.count - 5) more)" : "")")
        }
        if !modified.isEmpty {
            let fileNames = modified.prefix(5).map { ($0 as NSString).lastPathComponent }
            print("📝 GitRepositoryMonitor: Modified: \(fileNames.joined(separator: ", "))\(modified.count > 5 ? " (+ \(modified.count - 5) more)" : "")")
        }
    }

    /// Stop monitoring repository changes
    public func stopMonitoring() {
        if pollingTask != nil {
            print("🛑 GitRepositoryMonitor: Stopping monitoring for \(repoPath)")
        }

        pollingTask?.cancel()
        pollingTask = nil
        lastStatus = nil
        lastDiffHash = nil
    }

    deinit {
        pollingTask?.cancel()
    }
}

/// Debounces rapid changes to prevent UI thrashing during batch Git operations
private actor ChangeDebouncer {
    private var task: Task<Void, Never>?

    func debounce(
        interval: Duration = .milliseconds(500),
        action: @escaping @Sendable () async -> Void
    ) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
