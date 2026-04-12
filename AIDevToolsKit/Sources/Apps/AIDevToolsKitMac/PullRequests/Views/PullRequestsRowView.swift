import ClaudeChainService
import PRRadarModelsService
import SwiftUI

struct PullRequestsRowView: View {

    let metadata: PRMetadata
    let isFetching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metadata.displayNumber)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())

                stateLabel

                if isFetching {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                commentsBadge

                reviewStatusBadge

                buildStatusBadge

                if let relative = relativeTimestamp {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(metadata.title)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(2)

            if !metadata.headRefName.isEmpty {
                Text(metadata.headRefName)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !metadata.author.login.isEmpty {
                Text(metadata.author.name.isEmpty ? metadata.author.login : metadata.author.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("pullRequestRow_\(metadata.number)")
    }

    // MARK: - State Label

    @ViewBuilder
    private var stateLabel: some View {
        let prState = PRRadarModelsService.PRState(rawValue: metadata.state.uppercased()) ?? .open
        let (color, label) = stateDisplay(prState)
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func stateDisplay(_ state: PRRadarModelsService.PRState) -> (Color, String) {
        switch state {
        case .open:
            return (Color(red: 35/255, green: 134/255, blue: 54/255), "Open")
        case .merged:
            return (Color(red: 138/255, green: 86/255, blue: 221/255), "Merged")
        case .closed:
            return (Color(red: 218/255, green: 55/255, blue: 51/255), "Closed")
        case .draft:
            return (Color(red: 101/255, green: 108/255, blue: 118/255), "Draft")
        }
    }

    // MARK: - Comments Badge

    @ViewBuilder
    private var commentsBadge: some View {
        let count = (metadata.githubComments?.comments.count ?? 0)
            + (metadata.githubComments?.reviewComments.count ?? 0)
        if count > 0 {
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.secondary, in: Capsule())
                .help("\(count) comment\(count == 1 ? "" : "s")")
        }
    }

    // MARK: - Review Badges

    @ViewBuilder
    private var reviewStatusBadge: some View {
        if let status = reviewStatus {
            let approved = status.approvedBy.count
            let rejected = status.changesRequestedBy.count
            if approved == 0 && rejected == 0 {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Review Pending")
            } else {
                HStack(spacing: 3) {
                    if approved > 0 {
                        countBadge(approved, color: .green,
                                   help: "Approved by \(status.approvedBy.joined(separator: ", "))")
                    }
                    if rejected > 0 {
                        countBadge(rejected, color: .red,
                                   help: "Changes requested by \(status.changesRequestedBy.joined(separator: ", "))")
                    }
                }
            }
        }
    }

    private var reviewStatus: PRReviewStatus? {
        guard let reviews = metadata.reviews else { return nil }
        return PRReviewStatus(reviews: reviews)
    }

    // MARK: - Check Badges

    @ViewBuilder
    private var buildStatusBadge: some View {
        if metadata.isMergeable == false {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Merge Conflict")
        } else if let runs = metadata.checkRuns {
            let passing = runs.filter(\.isPassing).count
            let failing = runs.filter(\.isFailing).count
            let pending = runs.filter { $0.status != .completed }.count
            if passing == 0 && failing == 0 && pending == 0 {
                EmptyView()
            } else {
                HStack(spacing: 3) {
                    if passing > 0 {
                        countBadge(passing, color: .green,
                                   help: "\(passing) check\(passing == 1 ? "" : "s") passing")
                    }
                    if failing > 0 {
                        countBadge(failing, color: .red,
                                   help: "\(failing) check\(failing == 1 ? "" : "s") failing")
                    }
                    if pending > 0 && failing == 0 {
                        countBadge(pending, color: .orange,
                                   help: "\(pending) check\(pending == 1 ? "" : "s") pending")
                    }
                }
            }
        }
    }

    // MARK: - Shared Badge Helper

    private func countBadge(_ count: Int, color: Color, help: String) -> some View {
        Text("\(count)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color, in: Capsule())
            .help(help)
    }

    // MARK: - Timestamp

    private var relativeTimestamp: String? {
        guard !metadata.createdAt.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: metadata.createdAt)
            ?? ISO8601DateFormatter().date(from: metadata.createdAt)
        else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Open PR — enriched") {
    PullRequestsRowView(
        metadata: PRMetadata(
            number: 42,
            title: "Add unified GitHub PR loader with incremental updates",
            author: .init(login: "gestrich", name: "Bill Gestrich"),
            state: "OPEN",
            headRefName: "feature/unified-pr-loader",
            baseRefName: "main",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3 * 86400)),
            reviews: [.init(id: "r1", body: "", state: .approved, author: nil, submittedAt: nil)],
            checkRuns: [.init(name: "CI", status: .completed, conclusion: .success)]
        ),
        isFetching: false
    )
    .frame(width: 300)
    .padding()
}

#Preview("Fetching") {
    PullRequestsRowView(
        metadata: PRMetadata(
            number: 43,
            title: "Fix rate-limit handling in PR loader",
            author: .init(login: "gestrich", name: "Bill Gestrich"),
            state: "OPEN",
            headRefName: "fix/rate-limit",
            baseRefName: "main",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        ),
        isFetching: true
    )
    .frame(width: 300)
    .padding()
}
