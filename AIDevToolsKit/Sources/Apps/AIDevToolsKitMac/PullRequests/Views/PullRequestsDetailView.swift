import PRRadarModelsService
import SwiftUI

struct PullRequestsDetailView: View {

    let metadata: PRMetadata

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                if let reviews = metadata.reviews, !reviews.isEmpty {
                    reviewsSection(reviews)
                    Divider()
                }
                if let checkRuns = metadata.checkRuns, !checkRuns.isEmpty {
                    checkRunsSection(checkRuns)
                    Divider()
                }
                if let githubComments = metadata.githubComments {
                    let prComments = githubComments.comments
                    let reviewComments = githubComments.reviewComments
                    if !prComments.isEmpty || !reviewComments.isEmpty {
                        commentsSection(prComments: prComments, reviewComments: reviewComments)
                        Divider()
                    }
                }
                if let urlString = metadata.url, let url = URL(string: urlString) {
                    Link("Open on GitHub", destination: url)
                        .font(.body)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(metadata.displayNumber)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())

                stateLabel
            }

            Text(metadata.title)
                .font(.title3)
                .fontWeight(.semibold)

            if !metadata.headRefName.isEmpty {
                Text(metadata.headRefName)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }

            if !metadata.author.login.isEmpty {
                HStack(spacing: 6) {
                    GitHubAvatarView(author: metadata.author, size: 20)
                    let displayName = metadata.author.name.isEmpty ? metadata.author.login : metadata.author.name
                    Text(displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        let prState = PRState(rawValue: metadata.state.uppercased()) ?? .open
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

    private func stateDisplay(_ state: PRState) -> (Color, String) {
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

    // MARK: - Reviews

    private func reviewsSection(_ reviews: [GitHubReview]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviews")
                .font(.headline)
            ForEach(reviews, id: \.id) { review in
                HStack(spacing: 8) {
                    reviewStateIcon(review.state)
                    if let author = review.author {
                        GitHubAvatarView(author: author, size: 20)
                        Text(author.name ?? author.login)
                            .font(.body)
                    } else {
                        Text("Unknown")
                            .font(.body)
                    }
                    Spacer()
                    Text(review.state.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func reviewStateIcon(_ state: GitHubReviewState) -> some View {
        switch state {
        case .approved:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .changesRequested:
            Image(systemName: "xmark.seal.fill")
                .foregroundStyle(.red)
        case .commented:
            Image(systemName: "bubble.fill")
                .foregroundStyle(.secondary)
        case .dismissed:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Check Runs

    private func checkRunsSection(_ checkRuns: [GitHubCheckRun]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checks")
                .font(.headline)
            ForEach(checkRuns, id: \.name) { run in
                HStack(spacing: 8) {
                    checkRunIcon(run)
                    Text(run.name)
                        .font(.body)
                    Spacer()
                    Text(checkRunStatusLabel(run))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func checkRunIcon(_ run: GitHubCheckRun) -> some View {
        switch run.conclusion {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled, .timedOut:
            Image(systemName: "slash.circle.fill")
                .foregroundStyle(.secondary)
        default:
            if run.status == .inProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Comments

    private func commentsSection(prComments: [GitHubComment], reviewComments: [GitHubReviewComment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comments")
                .font(.headline)
            ForEach(prComments, id: \.id) { comment in
                commentRow(
                    author: comment.author.map { $0.name.flatMap { $0.isEmpty ? nil : $0 } ?? $0.login } ?? "Unknown",
                    body: comment.body,
                    location: nil
                )
            }
            ForEach(reviewComments) { comment in
                let location: String = {
                    let line = comment.line.map { ":\($0)" } ?? ""
                    return comment.path + line
                }()
                commentRow(
                    author: comment.author.map { $0.name.flatMap { $0.isEmpty ? nil : $0 } ?? $0.login } ?? "Unknown",
                    body: comment.bodyWithoutMetadata,
                    location: location
                )
            }
        }
    }

    private func commentRow(author: String, body: String, location: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(author)
                    .font(.caption)
                    .fontWeight(.semibold)
                if let location {
                    Text(location)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.leading, 4)
    }

    private func checkRunStatusLabel(_ run: GitHubCheckRun) -> String {
        if let conclusion = run.conclusion {
            switch conclusion {
            case .success: return "Passed"
            case .failure: return "Failed"
            case .cancelled: return "Cancelled"
            case .timedOut: return "Timed Out"
            case .neutral: return "Neutral"
            case .skipped: return "Skipped"
            }
        }
        switch run.status {
        case .inProgress: return "In Progress"
        case .queued: return "Queued"
        case .completed: return "Completed"
        }
    }
}

private extension GitHubReviewState {
    var displayName: String {
        switch self {
        case .approved: return "Approved"
        case .changesRequested: return "Changes Requested"
        case .commented: return "Commented"
        case .dismissed: return "Dismissed"
        case .pending: return "Pending"
        }
    }
}
