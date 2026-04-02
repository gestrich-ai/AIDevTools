public protocol TaskSource: Sendable {
    func nextTask() async throws -> PendingTask?
    func markComplete(_ task: PendingTask) async throws
}

public struct PendingTask: Sendable, Identifiable {
    public let id: String
    public let instructions: String
    public let skills: [String]

    public init(id: String, instructions: String, skills: [String]) {
        self.id = id
        self.instructions = instructions
        self.skills = skills
    }
}
