import SwiftUI

struct GlobalChatSidePanelView: View {
    @State private var chatContext: GlobalChatContext

    init(workingDirectory: String) {
        _chatContext = State(initialValue: GlobalChatContext(workingDirectory: workingDirectory))
    }

    var body: some View {
        ContextualChatPanel(context: chatContext)
    }
}

@MainActor
private final class GlobalChatContext: ViewChatContext {

    let chatContextIdentifier = "global"
    let chatWorkingDirectory: String
    let chatSystemPrompt = """
        You are an AI assistant embedded in the AIDevTools Mac app — a developer productivity tool \
        for AI-assisted software development, built in Swift/SwiftUI.

        The app is organized into tabs:
        - Architecture: Diagram and plan system architecture
        - Chains: Multi-step AI task automation (Claude Chain). Each chain has a spec file describing its tasks.
        - Evals: Evaluation harness for testing AI prompts and rules
        - Plans: Markdown-based implementation plan editor. Plans are files in the repo's docs/proposed/ directory.
        - PR Radar: Code review automation and pull request monitoring
        - Skills: Browser for agent skill files (.agents/skills/)

        You can help with any of the following:
        - Iterating on implementation plans: Read plan files, make requested changes, save updated files. \
        Distinguish brainstorming (just discuss) from edit requests (read, modify, save).
        - Claude Chain projects: Review spec files, discuss task structure, check chain status.
        - General development work in this repository.

        You have access to MCP tools:
        - get_ui_state: Check which chain or plan is currently open in the app
        - get_chain_status(name:): Check task completion status for a named chain

        The working directory is the root of the AIDevTools repository.
        """

    init(workingDirectory: String) {
        self.chatWorkingDirectory = workingDirectory
    }
}
