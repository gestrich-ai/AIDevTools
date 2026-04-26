import PRRadarCLIService
import PRRadarModelsService
import SwiftUI

struct RunListRow: View {
    let entry: RunHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedStartTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.4f", totalCostUsd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(rowTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text("\(entry.prEntries.count) PRs")
                Text("\(succeededCount) ✓  \(failedCount) ✗")
                    .monospacedDigit()
                if totalViolations > 0 {
                    Text("\(totalViolations) violations")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var succeededCount: Int {
        entry.prEntries.filter { $0.entry.status == .succeeded }.count
    }

    private var failedCount: Int {
        entry.prEntries.filter { $0.entry.status == .failed }.count
    }

    private var totalViolations: Int {
        entry.prEntries.compactMap(\.summary).map(\.violationsFound).reduce(0, +)
    }

    private var totalCostUsd: Double {
        entry.prEntries.compactMap(\.summary).map(\.totalCostUsd).reduce(0.0, +)
    }

    private var rowTitle: String {
        [entry.manifest.config, entry.manifest.rulesPathName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var formattedStartTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: entry.manifest.startedAt) {
            return date.formatted(.relative(presentation: .named))
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: entry.manifest.startedAt) {
            return date.formatted(.relative(presentation: .named))
        }
        return entry.manifest.startedAt
    }
}
