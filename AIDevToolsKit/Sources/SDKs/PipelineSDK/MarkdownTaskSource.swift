import Foundation

public struct MarkdownTaskSource: TaskSource {
    public let fileURL: URL
    public let format: MarkdownPipelineFormat
    public let taskIndex: Int?

    public init(fileURL: URL, format: MarkdownPipelineFormat, taskIndex: Int? = nil) {
        self.fileURL = fileURL
        self.format = format
        self.taskIndex = taskIndex
    }

    public func nextTask() async throws -> PendingTask? {
        let source = MarkdownPipelineSource(fileURL: fileURL, format: format, appendCreatePRStep: false)
        let pipeline = try await source.load()
        let steps = pipeline.steps.compactMap { $0 as? CodeChangeStep }

        if let index = taskIndex {
            guard let step = steps.first(where: { Int($0.id) == index && !$0.isCompleted }) else { return nil }
            return PendingTask(id: step.id, instructions: step.description, skills: step.skills)
        }

        guard let step = steps.first(where: { !$0.isCompleted }) else { return nil }
        return PendingTask(id: step.id, instructions: step.description, skills: step.skills)
    }

    public func markComplete(_ task: PendingTask) async throws {
        let source = MarkdownPipelineSource(fileURL: fileURL, format: format, appendCreatePRStep: false)
        let pipeline = try await source.load()
        let steps = pipeline.steps.compactMap { $0 as? CodeChangeStep }
        guard let step = steps.first(where: { $0.id == task.id }) else { return }
        try await source.markStepCompleted(step)
    }
}
