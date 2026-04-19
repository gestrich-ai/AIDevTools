import GitDiffModelsService
import GitSDK
import LocalDiffService
import Observation

@MainActor @Observable
final class CommitListDiffModel {
    private let diffService: LocalDiffService
    private let planPhaseDescriptions: [String]
    private let recentCommitLimit: Int
    private let repoPath: String
    private let workingDirectoryMonitor: GitWorkingDirectoryMonitor

    private(set) var diffState: DiffState = .empty(message: "Select a commit or working tree diff.")
    private(set) var entriesState: EntriesState = .loading
    private(set) var selectedFilePath: String?
    private(set) var selectedEntryIDs: Set<String> = []
    private var monitorTask: Task<Void, Never>?

    init(
        diffService: LocalDiffService,
        workingDirectoryMonitor: GitWorkingDirectoryMonitor,
        planPhaseDescriptions: [String] = [],
        recentCommitLimit: Int = 20,
        repoPath: String
    ) {
        self.diffService = diffService
        self.planPhaseDescriptions = planPhaseDescriptions
        self.recentCommitLimit = recentCommitLimit
        self.repoPath = repoPath
        self.workingDirectoryMonitor = workingDirectoryMonitor
    }

    var entries: [Entry] {
        guard case .loaded(let entries) = entriesState else { return [] }
        return entries
    }

    var changedFiles: [String] {
        guard case .loaded(let diff) = diffState else { return [] }
        return diff.changedFiles
    }

    var hasPlanCommitSelection: Bool {
        !planPhaseDescriptions.isEmpty
    }

    func load() async {
        await refreshEntries(showLoadingState: true, autoSelectFirstEntry: true, reloadDiffIfNeeded: true)
    }

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task {
            for await changes in workingDirectoryMonitor.changes(repoPath: repoPath) {
                guard !Task.isCancelled else { break }
                await refreshForWorkingDirectoryChanges(changes)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func select(entries entryIDs: Set<String>) async {
        guard selectedEntryIDs != entryIDs else { return }
        selectedEntryIDs = entryIDs
        await reloadDiff()
    }

    func selectPlanCommits() async {
        guard !planPhaseDescriptions.isEmpty else { return }
        do {
            let diffService = self.diffService
            let repoPath = self.repoPath
            let matchingCommits = try await Task.detached(priority: .userInitiated) {
                try await diffService.listCommitsMatching("Complete Phase", repoPath: repoPath)
            }.value
            let matchingHashes = Set(matchingCommits.compactMap { commit in
                planPhaseDescriptions.contains(where: { description in
                    commit.subject.hasSuffix(": \(description)")
                }) ? commit.hash : nil
            })
            let selectedIDs = Set<String>(entries.compactMap { entry in
                guard case .commit(let commit) = entry.kind else { return nil }
                return matchingHashes.contains(commit.hash) ? entry.id : nil
            })
            selectedEntryIDs = selectedIDs
            await reloadDiff()
        } catch {
            diffState = .error(error.localizedDescription)
        }
    }

    func setSelectedFilePath(_ path: String?) {
        guard selectedFilePath != path else { return }
        selectedFilePath = path
    }

    private func combinedDiff(from entries: [Entry]) async throws -> GitDiff {
        let selectedCommits = entries.compactMap { entry -> GitCommitSummary? in
            guard case .commit(let commit) = entry.kind else { return nil }
            return commit
        }
        let includeStaged = entries.contains { entry in
            if case .staged = entry.kind { return true }
            return false
        }
        let includeUnstaged = entries.contains { entry in
            if case .unstaged = entry.kind { return true }
            return false
        }
        let diffService = self.diffService
        let repoPath = self.repoPath

        return try await Task.detached(priority: .userInitiated) {
            var diffParts: [GitDiff] = []

            if selectedCommits.count > 1 {
                diffParts.append(
                    try await diffService.getCombinedDiff(
                        commits: selectedCommits.map(\.hash),
                        repoPath: repoPath
                    )
                )
            } else if let commit = selectedCommits.first {
                diffParts.append(try await diffService.getDiff(forCommit: commit.hash, repoPath: repoPath))
            }

            if includeStaged {
                diffParts.append(try await diffService.getStagedDiff(repoPath: repoPath))
            }
            if includeUnstaged {
                diffParts.append(try await diffService.getUnstagedDiff(repoPath: repoPath))
            }

            let rawDiff = diffParts
                .map(\.rawContent)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let commitHash = selectedCommits.map(\.hash).joined(separator: ",")
            return GitDiff.fromDiffContent(rawDiff, commitHash: commitHash)
        }.value
    }

    private func reloadDiff() async {
        let selectedEntries = entries.filter { selectedEntryIDs.contains($0.id) }
        guard !selectedEntries.isEmpty else {
            selectedFilePath = nil
            diffState = .empty(message: "Select a commit or working tree diff.")
            return
        }

        diffState = .loading
        do {
            let diff = try await combinedDiff(from: selectedEntries)
            if diff.rawContent.isEmpty {
                selectedFilePath = nil
                diffState = .empty(message: "No diff content is available for the current selection.")
            } else {
                if let selectedFilePath, diff.changedFiles.contains(selectedFilePath) {
                    self.selectedFilePath = selectedFilePath
                } else {
                    self.selectedFilePath = diff.changedFiles.first
                }
                diffState = .loaded(diff)
            }
        } catch {
            selectedFilePath = nil
            diffState = .error(error.localizedDescription)
        }
    }

    private func refreshEntries(
        showLoadingState: Bool,
        autoSelectFirstEntry: Bool,
        reloadDiffIfNeeded: Bool
    ) async {
        if showLoadingState {
            entriesState = .loading
        }

        do {
            let diffService = self.diffService
            let recentCommitLimit = self.recentCommitLimit
            let repoPath = self.repoPath
            let (unstagedDiff, stagedDiff, recentCommits) = try await Task.detached(priority: .userInitiated) {
                async let unstagedDiff = diffService.getUnstagedDiff(repoPath: repoPath)
                async let stagedDiff = diffService.getStagedDiff(repoPath: repoPath)
                async let recentCommits = diffService.listRecentCommits(limit: recentCommitLimit, repoPath: repoPath)
                return try await (unstagedDiff, stagedDiff, recentCommits)
            }.value

            var updatedEntries: [Entry] = []
            if !unstagedDiff.rawContent.isEmpty {
                updatedEntries.append(Entry(id: "unstaged", kind: .unstaged))
            }
            if !stagedDiff.rawContent.isEmpty {
                updatedEntries.append(Entry(id: "staged", kind: .staged))
            }
            updatedEntries.append(contentsOf: recentCommits.map { commit in
                Entry(id: "commit:\(commit.hash)", kind: .commit(commit))
            })

            let previousSelection = selectedEntryIDs
            let availableEntryIDs = Set(updatedEntries.map(\.id))
            var nextSelection = previousSelection.intersection(availableEntryIDs)

            if autoSelectFirstEntry, nextSelection.isEmpty, previousSelection.isEmpty, let firstEntry = updatedEntries.first {
                nextSelection = [firstEntry.id]
            }

            selectedEntryIDs = nextSelection
            entriesState = updatedEntries.isEmpty ? .empty : .loaded(updatedEntries)

            guard !nextSelection.isEmpty else {
                selectedFilePath = nil
                diffState = .empty(message: "Select a commit or working tree diff.")
                return
            }

            if reloadDiffIfNeeded || nextSelection != previousSelection {
                await reloadDiff()
            }
        } catch {
            entriesState = .error(error.localizedDescription)
            diffState = .error(error.localizedDescription)
        }
    }

    private func refreshForWorkingDirectoryChanges(_ changes: Set<GitWorkingDirectoryChange>) async {
        let shouldReloadDiff =
            (changes.contains(.index) && selectedEntryIDs.contains("staged")) ||
            (changes.contains(.workingTree) && selectedEntryIDs.contains("unstaged"))

        await refreshEntries(
            showLoadingState: false,
            autoSelectFirstEntry: false,
            reloadDiffIfNeeded: shouldReloadDiff
        )
    }

    enum DiffState {
        case empty(message: String)
        case error(String)
        case loaded(GitDiff)
        case loading
    }

    enum EntriesState {
        case empty
        case error(String)
        case loaded([Entry])
        case loading
    }

    struct Entry: Identifiable, Equatable {
        enum Kind: Equatable {
            case commit(GitCommitSummary)
            case staged
            case unstaged
        }

        let id: String
        let kind: Kind

        var detailText: String {
            switch kind {
            case .commit(let commit):
                commit.hash.prefix(7).description
            case .staged:
                "Index"
            case .unstaged:
                "Working tree"
            }
        }

        var title: String {
            switch kind {
            case .commit(let commit):
                commit.subject
            case .staged:
                "Staged changes"
            case .unstaged:
                "Unstaged changes"
            }
        }
    }
}
