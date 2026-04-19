import GitSDK
import LocalDiffService
import Observation
import PRRadarModelsService

@MainActor @Observable
final class CommitListDiffModel {
    enum DiffState {
        case empty(message: String)
        case error(String)
        case loaded(GitDiff)
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

    enum EntriesState {
        case empty
        case error(String)
        case loaded([Entry])
        case loading
    }

    private let diffService: LocalDiffService
    private let planPhaseDescriptions: [String]
    private let recentCommitLimit: Int
    private let repoPath: String

    private(set) var diffState: DiffState = .empty(message: "Select a commit or working tree diff.")
    private(set) var entriesState: EntriesState = .loading
    private(set) var selectedEntryIDs: Set<String> = []

    init(
        diffService: LocalDiffService,
        planPhaseDescriptions: [String] = [],
        recentCommitLimit: Int = 20,
        repoPath: String
    ) {
        self.diffService = diffService
        self.planPhaseDescriptions = planPhaseDescriptions
        self.recentCommitLimit = recentCommitLimit
        self.repoPath = repoPath
    }

    var entries: [Entry] {
        guard case .loaded(let entries) = entriesState else { return [] }
        return entries
    }

    var hasPlanCommitSelection: Bool {
        !planPhaseDescriptions.isEmpty
    }

    func load() async {
        entriesState = .loading
        do {
            let unstagedDiff = try await diffService.getUnstagedDiff(repoPath: repoPath)
            let stagedDiff = try await diffService.getStagedDiff(repoPath: repoPath)
            let recentCommits = try await diffService.listRecentCommits(limit: recentCommitLimit, repoPath: repoPath)

            var entries: [Entry] = []
            if !unstagedDiff.rawContent.isEmpty {
                entries.append(Entry(id: "unstaged", kind: .unstaged))
            }
            if !stagedDiff.rawContent.isEmpty {
                entries.append(Entry(id: "staged", kind: .staged))
            }
            entries.append(contentsOf: recentCommits.map { commit in
                Entry(id: "commit:\(commit.hash)", kind: .commit(commit))
            })

            entriesState = entries.isEmpty ? .empty : .loaded(entries)
            if selectedEntryIDs.isEmpty, let firstEntry = entries.first {
                selectedEntryIDs = [firstEntry.id]
                await reloadDiff()
            } else {
                selectedEntryIDs = selectedEntryIDs.intersection(Set(entries.map(\.id)))
                if selectedEntryIDs.isEmpty {
                    diffState = .empty(message: "Select a commit or working tree diff.")
                } else {
                    await reloadDiff()
                }
            }
        } catch {
            entriesState = .error(error.localizedDescription)
            diffState = .error(error.localizedDescription)
        }
    }

    func select(entries entryIDs: Set<String>) async {
        selectedEntryIDs = entryIDs
        await reloadDiff()
    }

    func selectPlanCommits() async {
        guard !planPhaseDescriptions.isEmpty else { return }
        do {
            let matchingCommits = try await diffService.listCommitsMatching("Complete Phase", repoPath: repoPath)
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

    private func combinedDiff(from entries: [Entry]) async throws -> GitDiff {
        var diffParts: [GitDiff] = []
        let selectedCommits = entries.compactMap { entry -> GitCommitSummary? in
            guard case .commit(let commit) = entry.kind else { return nil }
            return commit
        }

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

        for entry in entries {
            switch entry.kind {
            case .commit:
                continue
            case .staged:
                diffParts.append(try await diffService.getStagedDiff(repoPath: repoPath))
            case .unstaged:
                diffParts.append(try await diffService.getUnstagedDiff(repoPath: repoPath))
            }
        }

        let rawDiff = diffParts
            .map(\.rawContent)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let commitHash = selectedCommits.map(\.hash).joined(separator: ",")
        return GitDiff.fromDiffContent(rawDiff, commitHash: commitHash)
    }

    private func reloadDiff() async {
        let selectedEntries = entries.filter { selectedEntryIDs.contains($0.id) }
        guard !selectedEntries.isEmpty else {
            diffState = .empty(message: "Select a commit or working tree diff.")
            return
        }

        diffState = .loading
        do {
            let diff = try await combinedDiff(from: selectedEntries)
            if diff.rawContent.isEmpty {
                diffState = .empty(message: "No diff content is available for the current selection.")
            } else {
                diffState = .loaded(diff)
            }
        } catch {
            diffState = .error(error.localizedDescription)
        }
    }
}
