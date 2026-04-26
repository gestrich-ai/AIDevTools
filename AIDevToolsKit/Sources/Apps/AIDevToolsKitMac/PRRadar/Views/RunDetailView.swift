import PRRadarCLIService
import PRRadarModelsService
import SwiftUI

struct RunDetailView: View {
    let entry: RunHistoryEntry?
    @Environment(PRRadarNavigationModel.self) private var navigationModel
    @Environment(\.runsModel) private var runsModel

    var body: some View {
        if let entry {
            historicalRunDetail(entry: entry)
        } else if let model = runsModel {
            liveRunContent(model: model)
        } else {
            noSelectionView
        }
    }

    // MARK: - Historical

    @ViewBuilder
    private func historicalRunDetail(entry: RunHistoryEntry) -> some View {
        let sorted = entry.prEntries.sorted {
            ($0.summary?.totalDurationMs ?? 0) > ($1.summary?.totalDurationMs ?? 0)
        }
        List {
            ForEach(sorted, id: \.entry.prNumber) { prEntry in
                prRow(prEntry)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func prRow(_ prEntry: RunAllPREntry) -> some View {
        HStack(spacing: 8) {
            statusIcon(prEntry.entry.status)
                .frame(width: 16)
            Text("#\(prEntry.entry.prNumber)")
                .font(.body.monospacedDigit())
                .fontWeight(.medium)
                .frame(width: 52, alignment: .leading)
            Text(prEntry.entry.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let summary = prEntry.summary {
                Text(summary.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                Text("\(summary.violationsFound)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(summary.violationsFound > 0 ? .orange : .secondary)
                    .frame(width: 28, alignment: .trailing)
                Text("$\(String(format: "%.4f", summary.totalCostUsd))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
            if let reason = prEntry.entry.failureReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigationModel.selectPR(number: prEntry.entry.prNumber)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: PRRunStatus) -> some View {
        switch status {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Live Run

    @ViewBuilder
    private func liveRunContent(model: RunsModel) -> some View {
        switch model.liveRunState {
        case .idle:
            noSelectionView
        case .running(let logs, let current, let total):
            liveRunView(logs: logs, current: current, total: total)
        case .completed(let completedEntry):
            historicalRunDetail(entry: completedEntry)
        case .failed(let error):
            ContentUnavailableView(
                "Run Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        }
    }

    @ViewBuilder
    private func liveRunView(logs: String, current: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Processing PR \(current) of \(total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("logBottom")
                }
                .onChange(of: logs) { _, _ in
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - No Selection

    private var noSelectionView: some View {
        ContentUnavailableView(
            "Select a Run",
            systemImage: "clock.arrow.circlepath",
            description: Text("Choose a run from the list to view its details.")
        )
    }
}
