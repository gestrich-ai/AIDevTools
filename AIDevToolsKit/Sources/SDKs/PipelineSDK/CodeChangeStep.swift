import Foundation

public struct CodeChangeStep: PipelineStep {
    public let id: String
    public let description: String
    public let isCompleted: Bool
    public let prompt: String
    public let skills: [String]
    public let context: CodeChangeContext

    public init(
        id: String,
        description: String,
        isCompleted: Bool,
        prompt: String,
        skills: [String],
        context: CodeChangeContext
    ) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
        self.prompt = prompt
        self.skills = skills
        self.context = context
    }
}