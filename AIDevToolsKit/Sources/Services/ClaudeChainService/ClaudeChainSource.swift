import PipelineSDK

/// Unified protocol for ClaudeChain task sources covering both execution and display.
///
/// Extends `TaskSource` so any implementation is usable by `PipelineRunner`'s
/// `drainTaskSource` loop. GitHub service should be injected at construction
/// time and used by `loadDetail()`.
public protocol ClaudeChainSource: TaskSource {
    /// Short label shown in UI to distinguish source types, e.g. "sweep". Nil for standard chains.
    var kindBadge: String? { get }
    /// Project name, accessible synchronously.
    var projectName: String { get }
    /// Relative base path of the project directory (e.g. "claude-chain/my-project"), accessible synchronously.
    var projectBasePath: String { get }
    func loadProject() async throws -> ChainProject
    func loadDetail() async throws -> ChainProjectDetail
}
