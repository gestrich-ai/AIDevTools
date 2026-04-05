import Foundation

public struct ChainListResult: Sendable {
    public let projects: [ChainProject]
    public let failures: [ChainFetchFailure]

    public init(projects: [ChainProject], failures: [ChainFetchFailure] = []) {
        self.projects = projects
        self.failures = failures
    }
}

public struct ChainFetchFailure: Error, LocalizedError, Sendable {
    public let context: String
    public let underlyingDescription: String

    public init(context: String, underlyingError: Error) {
        self.context = context
        self.underlyingDescription = underlyingError.localizedDescription
    }

    public var errorDescription: String? {
        "\(context): \(underlyingDescription)"
    }
}
