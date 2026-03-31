import Foundation
import PRRadarModelsService

actor GitHubPRCacheService {
    private let rootURL: URL
    nonisolated let stream: AsyncStream<Int>
    private nonisolated let continuation: AsyncStream<Int>.Continuation

    init(rootURL: URL) {
        self.rootURL = rootURL
        (stream, continuation) = AsyncStream<Int>.makeStream()
    }

    func readPR(number: Int) throws -> GitHubPullRequest? {
        try readFile(at: prURL(number: number))
    }

    func readComments(number: Int) throws -> GitHubPullRequestComments? {
        try readFile(at: commentsURL(number: number))
    }

    func readRepository() throws -> GitHubRepository? {
        try readFile(at: repositoryURL())
    }

    func writePR(_ pr: GitHubPullRequest, number: Int) throws {
        try writePRFile(pr, to: prURL(number: number), prNumber: number)
    }

    func writeComments(_ comments: GitHubPullRequestComments, number: Int) throws {
        try writePRFile(comments, to: commentsURL(number: number), prNumber: number)
    }

    func writeRepository(_ repository: GitHubRepository) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(repository)
        try data.write(to: repositoryURL())
    }

    func readCheckRuns(number: Int) throws -> [GitHubCheckRun]? {
        try readFile(at: checkRunsURL(number: number))
    }

    func writeCheckRuns(_ checkRuns: [GitHubCheckRun], number: Int) throws {
        try writePRFile(checkRuns, to: checkRunsURL(number: number), prNumber: number)
    }

    func readReviews(number: Int) throws -> [GitHubReview]? {
        try readFile(at: reviewsURL(number: number))
    }

    func writeReviews(_ reviews: [GitHubReview], number: Int) throws {
        try writePRFile(reviews, to: reviewsURL(number: number), prNumber: number)
    }

    // MARK: - Index

    func readIndex(key: String) throws -> [Int]? {
        try readFile(at: indexURL(key: key))
    }

    func writeIndex(_ numbers: [Int], key: String) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(numbers)
        try data.write(to: indexURL(key: key))
    }

    // MARK: - Private helpers

    private func readFile<T: Decodable>(at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func writePRFile<T: Encodable>(_ value: T, to url: URL, prNumber: Int) throws {
        try FileManager.default.createDirectory(at: prDirectory(number: prNumber), withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(value)
        try data.write(to: url)
        continuation.yield(prNumber)
    }

    // MARK: - URLs

    private func prDirectory(number: Int) -> URL {
        rootURL.appendingPathComponent(String(number))
    }

    private func prURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-pr.json")
    }

    private func checkRunsURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-checks.json")
    }

    private func commentsURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-comments.json")
    }

    private func indexURL(key: String) -> URL {
        rootURL.appendingPathComponent("index-\(key).json")
    }

    private func repositoryURL() -> URL {
        rootURL.appendingPathComponent("gh-repo.json")
    }

    private func reviewsURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-reviews.json")
    }
}

