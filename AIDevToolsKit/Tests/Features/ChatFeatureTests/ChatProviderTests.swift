import AIOutputSDK
import Foundation
import Testing
@testable import ChatFeature

struct ChatProviderOptionsTests {

    @Test func defaultValues() {
        let options = ChatProviderOptions()
        #expect(options.dangerouslySkipPermissions == false)
        #expect(options.model == nil)
        #expect(options.sessionId == nil)
        #expect(options.systemPrompt == nil)
        #expect(options.workingDirectory == nil)
    }

    @Test func customValues() {
        let options = ChatProviderOptions(
            dangerouslySkipPermissions: true,
            model: "claude-sonnet-4-20250514",
            sessionId: "abc-123",
            systemPrompt: "You are a helpful assistant.",
            workingDirectory: "/tmp"
        )
        #expect(options.dangerouslySkipPermissions == true)
        #expect(options.model == "claude-sonnet-4-20250514")
        #expect(options.sessionId == "abc-123")
        #expect(options.systemPrompt == "You are a helpful assistant.")
        #expect(options.workingDirectory == "/tmp")
    }
}

struct ChatProviderResultTests {

    @Test func storesContentAndSessionId() {
        let result = ChatProviderResult(content: "Hello!", sessionId: "session-1")
        #expect(result.content == "Hello!")
        #expect(result.sessionId == "session-1")
    }

    @Test func allowsNilSessionId() {
        let result = ChatProviderResult(content: "Response", sessionId: nil)
        #expect(result.content == "Response")
        #expect(result.sessionId == nil)
    }
}

private actor MockChatProvider: ChatProvider {
    let displayName = "Mock"
    let name = "mock"
    var sendMessageCalled = false
    var lastMessage: String?
    var lastImages: [ImageAttachment] = []

    func sendMessage(
        _ message: String,
        images: [ImageAttachment],
        options: ChatProviderOptions,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> ChatProviderResult {
        sendMessageCalled = true
        lastMessage = message
        lastImages = images
        onStreamEvent?(.textDelta("Hello"))
        return ChatProviderResult(content: "Hello", sessionId: "s1")
    }
}

struct ChatProviderProtocolTests {

    @Test func defaultSupportsSessionHistoryIsFalse() async {
        let provider = MockChatProvider()
        #expect(provider.supportsSessionHistory == false)
    }

    @Test func defaultListSessionsReturnsEmpty() async {
        let provider = MockChatProvider()
        let sessions = await provider.listSessions(workingDirectory: "/tmp")
        #expect(sessions.isEmpty)
    }

    @Test func defaultLoadSessionMessagesReturnsEmpty() async {
        let provider = MockChatProvider()
        let messages = await provider.loadSessionMessages(sessionId: "any", workingDirectory: "/tmp")
        #expect(messages.isEmpty)
    }

    @Test func defaultCancelDoesNotThrow() async {
        let provider = MockChatProvider()
        await provider.cancel()
    }

    @Test func sendMessagePassesArguments() async throws {
        let provider = MockChatProvider()
        let image = ImageAttachment(base64Data: "abc", mediaType: "image/png")
        let options = ChatProviderOptions(sessionId: "s1", workingDirectory: "/tmp")

        let result = try await provider.sendMessage(
            "Hello",
            images: [image],
            options: options,
            onStreamEvent: nil
        )

        #expect(result.content == "Hello")
        #expect(result.sessionId == "s1")
        #expect(await provider.sendMessageCalled == true)
        #expect(await provider.lastMessage == "Hello")
        #expect(await provider.lastImages.count == 1)
    }

    @Test func sendMessageInvokesStreamCallback() async throws {
        let provider = MockChatProvider()
        var receivedEvents: [AIStreamEvent] = []

        _ = try await provider.sendMessage(
            "Test",
            images: [],
            options: ChatProviderOptions(),
            onStreamEvent: { event in
                receivedEvents.append(event)
            }
        )

        #expect(receivedEvents.count == 1)
    }
}
