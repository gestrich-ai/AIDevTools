public protocol ChainProjectSource: Sendable {
    func listChains() async throws -> ChainListResult
}
