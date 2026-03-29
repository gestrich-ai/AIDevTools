public enum MarkdownPipelineFormat: Sendable {
    /// MarkdownPlanner format: `## - [ ] Phase name`
    case phase
    /// ClaudeChain format: `- [ ] Task description`
    case task
}