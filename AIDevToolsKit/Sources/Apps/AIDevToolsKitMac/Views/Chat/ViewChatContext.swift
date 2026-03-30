/// Context protocol that views implement to provide the chat panel with view-specific information.
@MainActor
protocol ViewChatContext: AnyObject {
    /// Stable identifier for this context. Used to key chat sessions.
    var chatContextIdentifier: String { get }
    /// Brief description of the current view context.
    var chatSystemPrompt: String { get }
    /// Working directory for CLI commands.
    var chatWorkingDirectory: String { get }
}
