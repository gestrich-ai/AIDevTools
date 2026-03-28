import AIOutputSDK
import Foundation
import Testing
@testable import ChatFeature

struct ChatMessageTests {

    // MARK: - contentBlocks

    @Test func contentBlocksFromStringInit() {
        let message = ChatMessage(role: .assistant, content: "Hello world")
        #expect(message.contentBlocks == [.text("Hello world")])
    }

    @Test func contentBlocksFromEmptyStringInit() {
        let message = ChatMessage(role: .assistant, content: "")
        #expect(message.contentBlocks.isEmpty)
    }

    @Test func contentBlocksFromDirectInit() {
        let blocks: [AIContentBlock] = [
            .thinking("Let me think..."),
            .toolUse(name: "Bash", detail: "ls -la"),
            .text("Here is the result."),
        ]
        let message = ChatMessage(role: .assistant, contentBlocks: blocks)
        #expect(message.contentBlocks == blocks)
    }

    // MARK: - content (computed)

    @Test func contentConcatenatesTextBlocks() {
        let blocks: [AIContentBlock] = [
            .thinking("hmm"),
            .text("Hello "),
            .toolUse(name: "Bash", detail: "ls"),
            .text("world"),
        ]
        let message = ChatMessage(role: .assistant, contentBlocks: blocks)
        #expect(message.content == "Hello world")
    }

    @Test func contentReturnsEmptyForNoTextBlocks() {
        let blocks: [AIContentBlock] = [
            .thinking("hmm"),
            .toolUse(name: "Bash", detail: "ls"),
        ]
        let message = ChatMessage(role: .assistant, contentBlocks: blocks)
        #expect(message.content == "")
    }

    // MARK: - shouldCollapseThinking

    @Test func shouldCollapseThinkingReturnsTrueForCompletedMessageWithBothTypes() {
        let blocks: [AIContentBlock] = [.thinking("Thinking"), .text("Here is the answer.")]
        let message = ChatMessage(role: .assistant, contentBlocks: blocks, isComplete: true)
        #expect(message.shouldCollapseThinking == true)
    }

    @Test func shouldCollapseThinkingReturnsFalseForIncompleteMessage() {
        let blocks: [AIContentBlock] = [.thinking("Thinking"), .text("Here is the answer.")]
        let message = ChatMessage(role: .assistant, contentBlocks: blocks, isComplete: false)
        #expect(message.shouldCollapseThinking == false)
    }

    @Test func shouldCollapseThinkingReturnsFalseForUserMessage() {
        let message = ChatMessage(role: .user, content: "Not thinking", isComplete: true)
        #expect(message.shouldCollapseThinking == false)
    }

    @Test func shouldCollapseThinkingReturnsFalseWhenOnlyThinking() {
        let blocks: [AIContentBlock] = [.thinking("Just thinking")]
        let message = ChatMessage(role: .assistant, contentBlocks: blocks, isComplete: true)
        #expect(message.shouldCollapseThinking == false)
    }

    @Test func shouldCollapseThinkingReturnsTrueWithToolBlocks() {
        let blocks: [AIContentBlock] = [
            .toolUse(name: "Bash", detail: "ls"),
            .toolResult(name: "Bash", summary: "file.txt", isError: false),
            .text("Done."),
        ]
        let message = ChatMessage(role: .assistant, contentBlocks: blocks, isComplete: true)
        #expect(message.shouldCollapseThinking == true)
    }
}
