import GitSDK
import GitUIToolkit
import LocalDiffService
import SwiftUI

struct CommitListDiffView: View {
    @State private var model: CommitListDiffModel

    init(
        diffService: LocalDiffService,
        workingDirectoryMonitor: GitWorkingDirectoryMonitor = GitWorkingDirectoryMonitor(),
        planPhaseDescriptions: [String] = [],
        recentCommitLimit: Int = 20,
        repoPath: String
    ) {
        _model = State(initialValue: CommitListDiffModel(
            diffService: diffService,
            workingDirectoryMonitor: workingDirectoryMonitor,
            planPhaseDescriptions: planPhaseDescriptions,
            recentCommitLimit: recentCommitLimit,
            repoPath: repoPath
        ))
    }

    var body: some View {
        VSplitView {
            commitList
                .frame(minHeight: 180, idealHeight: 220)

            diffContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await model.load()
            model.startMonitoring()
        }
        .onDisappear {
            model.stopMonitoring()
        }
    }

    private var commitList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diff Sources")
                    .font(.headline)

                Spacer()

                if model.hasPlanCommitSelection {
                    Button("All plan commits") {
                        Task { await model.selectPlanCommits() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            switch model.entriesState {
            case .empty:
                ContentUnavailableView(
                    "No Diffs Available",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("There are no recent commits or working tree changes to show.")
                )
            case .error(let error):
                ContentUnavailableView(
                    "Failed to Load Diffs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            case .loaded(let entries):
                List(selection: Binding(
                    get: { model.selectedEntryIDs },
                    set: { newSelection in
                        Task { await model.select(entries: newSelection) }
                    }
                )) {
                    if containsWorkingTreeEntries(in: entries) {
                        Section("Working Tree") {
                            ForEach(entries.filter(isWorkingTreeEntry)) { entry in
                                row(for: entry)
                                    .tag(entry.id)
                            }
                        }
                    }

                    let commits = entries.filter(isCommitEntry)
                    if !commits.isEmpty {
                        Section("Recent Commits") {
                            ForEach(commits) { entry in
                                row(for: entry)
                                    .tag(entry.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            case .loading:
                ProgressView("Loading diffs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var diffContent: some View {
        switch model.diffState {
        case .empty(let message):
            ContentUnavailableView(
                "No Diff Selected",
                systemImage: "arrow.up.left.and.arrow.down.right",
                description: Text(message)
            )
        case .error(let error):
            ContentUnavailableView(
                "Failed to Load Diff",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        case .loaded(let diff):
            GitDiffView(diff: diff)
        case .loading:
            ProgressView("Loading diff…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func containsWorkingTreeEntries(in entries: [CommitListDiffModel.Entry]) -> Bool {
        entries.contains(where: isWorkingTreeEntry)
    }

    private func isCommitEntry(_ entry: CommitListDiffModel.Entry) -> Bool {
        if case .commit = entry.kind {
            return true
        }
        return false
    }

    private func isWorkingTreeEntry(_ entry: CommitListDiffModel.Entry) -> Bool {
        switch entry.kind {
        case .commit:
            false
        case .staged, .unstaged:
            true
        }
    }

    private func row(for entry: CommitListDiffModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.body)
                .lineLimit(1)

            Text(entry.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
