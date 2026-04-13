import Foundation

@MainActor @Observable
final class ExecutionPanelModel {
    enum Segment: Hashable {
        case chat
        case output
    }

    var isVisible = false
    var selectedSegment: Segment = .chat
    private(set) var executionChatModel: ChatModel?

    func showOutput(with chatModel: ChatModel) {
        executionChatModel = chatModel
        selectedSegment = .output
        isVisible = true
    }

    func clearOutput() {
        executionChatModel = nil
    }
}
