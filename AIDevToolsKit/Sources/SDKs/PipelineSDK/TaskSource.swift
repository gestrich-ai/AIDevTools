public protocol TaskSource: Sendable {
    func nextTask() async throws -> PendingTask?
    func markComplete(_ task: PendingTask) async throws
}

public struct PendingTask: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let instructions: String
    public let skills: [String]

    public init(id: String, displayName: String, instructions: String, skills: [String]) {
        self.id = id
        self.displayName = displayName
        self.instructions = instructions
        self.skills = skills
    }
}
