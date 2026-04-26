import PRRadarCLIService
import SwiftUI

struct RunsListView: View {
    @Environment(\.runsModel) private var runsModel
    @Binding var selectedRun: RunHistoryEntry?

    var body: some View {
        if let model = runsModel {
            listContent(model: model)
        } else {
            ContentUnavailableView(
                "Runs Not Available",
                systemImage: "clock.badge.xmark",
                description: Text("PR Radar is not configured for this repository.")
            )
        }
    }

    @ViewBuilder
    private func listContent(model: RunsModel) -> some View {
        if model.runs.isEmpty && !isLiveRunActive(model) {
            ContentUnavailableView(
                "No Runs Found",
                systemImage: "clock",
                description: Text("No PR Radar runs have been recorded for this repository.")
            )
        } else {
            List(selection: $selectedRun) {
                liveRunSection(model: model)
                ForEach(model.runs) { entry in
                    RunListRow(entry: entry)
                        .tag(Optional(entry))
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func liveRunSection(model: RunsModel) -> some View {
        switch model.liveRunState {
        case .running(_, let current, let total):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Running...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("PR \(current) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .tag(Optional<RunHistoryEntry>.none)
        case .failed(let error):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run Failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
            .tag(Optional<RunHistoryEntry>.none)
        case .idle, .completed:
            EmptyView()
        }
    }

    private func isLiveRunActive(_ model: RunsModel) -> Bool {
        switch model.liveRunState {
        case .running, .failed: return true
        case .idle, .completed: return false
        }
    }
}
