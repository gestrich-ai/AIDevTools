public protocol PipelineStep: Sendable {
    var id: String { get }
    var description: String { get }
    var isCompleted: Bool { get }
}
