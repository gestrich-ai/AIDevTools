/// How a skill invocation was detected during eval grading.
public enum InvocationMethod: String, Codable, Sendable {
    /// The provider lacks a dedicated skill tool, so invocation is inferred from
    /// the skill file appearing in trace commands. Cannot confirm intent.
    case inferred
    /// The skill file was read without using the Skill tool — found during exploration.
    case discovered
    /// The AI used a dedicated Skill tool to invoke the skill (Claude only).
    case explicit
}
