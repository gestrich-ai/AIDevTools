import AIOutputSDK
import ChatFeature
import Foundation
import Observation
import PipelineSDK

@Observable
@MainActor
public final class ChatModel {
    public private(set) var messages: [ChatMessage] = []
    public private(set) var state: ModelState = .idle
    public private(set) var messageQueue: [QueuedMessage] = []
    public let providerDisplayName: String
    public let providerIcon: AIProviderIcon?
    public let providerName: String
    public let settings: ChatSettings
    public private(set) var workingDirectory: String
    public private(set) var currentStreamingMessageId: UUID?

    public var currentSessionId: String? { sessionId }
    public var isLoadingHistory: Bool { state == .loadingHistory }
    public var isProcessing: Bool { state == .processing }

    private let getSessionDetailsUseCase: GetSessionDetailsUseCase
    private let listSessionsUseCase: ListSessionsUseCase
    private let loadSessionMessagesUseCase: LoadSessionMessagesUseCase
    private let mcpConfigPath: String?
    private let resumeLatestSessionUseCase: ResumeLatestSessionUseCase
    private let sendMessageUseCase: SendChatMessageUseCase
    private let systemPrompt: String?
    private var currentConsumeTask: Task<Void, Never>?
    private var currentTask: Task<Void, Never>?
    public private(set) var hasStartedSession: Bool = false
    private var sessionId: String?

    public init(
        getSessionDetailsUseCase: GetSessionDetailsUseCase,
        listSessionsUseCase: ListSessionsUseCase,
        loadSessionMessagesUseCase: LoadSessionMessagesUseCase,
        resumeLatestSessionUseCase: ResumeLatestSessionUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        providerDisplayName: String,
        providerIcon: AIProviderIcon?,
        providerName: String,
        workingDirectory: String?,
        mcpConfigPath: String? = nil,
        settings: ChatSettings = ChatSettings(),
        systemPrompt: String? = nil
    ) {
        self.getSessionDetailsUseCase = getSessionDetailsUseCase
        self.listSessionsUseCase = listSessionsUseCase
        self.loadSessionMessagesUseCase = loadSessionMessagesUseCase
        self.mcpConfigPath = mcpConfigPath
        self.resumeLatestSessionUseCase = resumeLatestSessionUseCase
        self.sendMessageUseCase = sendMessageUseCase
        self.settings = settings
        self.providerDisplayName = providerDisplayName
        self.providerIcon = providerIcon
        self.providerName = providerName
        self.systemPrompt = systemPrompt

        let rawWorkingDir = workingDirectory ?? FileManager.default.currentDirectoryPath
        self.workingDirectory = Self.resolveSymlinks(in: rawWorkingDir)

        if settings.resumeLastSession {
            self.state = .loadingHistory
            let workDir = self.workingDirectory
            Task {
                await resumeLatestSession(workingDirectory: workDir)
                if self.workingDirectory == workDir {
                    self.state = .idle
                }
            }
        }
    }

    public convenience init(configuration: ChatModelConfiguration) {
        let client = configuration.client
        self.init(
            getSessionDetailsUseCase: GetSessionDetailsUseCase(client: client),
            listSessionsUseCase: ListSessionsUseCase(client: client),
            loadSessionMessagesUseCase: LoadSessionMessagesUseCase(client: client),
            resumeLatestSessionUseCase: ResumeLatestSessionUseCase(client: client),
            sendMessageUseCase: SendChatMessageUseCase(client: client),
            providerDisplayName: client.displayName,
            providerIcon: client.icon,
            providerName: client.name,
            workingDirectory: configuration.workingDirectory,
            mcpConfigPath: configuration.mcpConfigPath,
            settings: configuration.settings,
            systemPrompt: configuration.systemPrompt
        )
    }

    // MARK: - Public API

    public func sendMessage(_ content: String, images: [ImageAttachment] = []) {
        guard !content.isEmpty || !images.isEmpty else { return }

        if isProcessing {
            messageQueue.append(QueuedMessage(content: content, images: images))
            return
        }

        currentTask = Task {
            await sendMessageInternal(content, images: images)
        }
    }

    public func startNewConversation() {
        messages.removeAll()
        sessionId = nil
        hasStartedSession = false
        messageQueue.removeAll()
    }

    public func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        currentConsumeTask?.cancel()
        currentConsumeTask = nil
        state = .idle
        if let id = currentStreamingMessageId,
           let index = messages.firstIndex(where: { $0.id == id }),
           messages[index].contentBlocks.isEmpty {
            messages.remove(at: index)
            currentStreamingMessageId = nil
        } else {
            finalizeCurrentStreamingMessage()
        }
    }

    public func clearMessages() {
        messages.removeAll()
    }

    public func removeQueuedMessage(id: UUID) {
        messageQueue.removeAll { $0.id == id }
    }

    public func clearQueue() {
        messageQueue.removeAll()
    }

    // MARK: - Programmatic Message Injection

    public func handlePipelineEvent(_ event: PipelineEvent) {
        switch event {
        case .nodeStarted:
            finalizeCurrentStreamingMessage()
        case .nodeProgress(_, let progress):
            switch progress {
            case .userPrompt(let prompt):
                appendUserMessage(prompt)
                beginStreamingMessage()
            case .contentBlocks(let blocks):
                updateCurrentStreamingBlocks(blocks)
            default:
                break
            }
        case .nodeCompleted:
            finalizeCurrentStreamingMessage()
        default:
            break
        }
    }

    public func appendUserMessage(_ content: String) {
        messages.append(ChatMessage(role: .user, content: content, isComplete: true))
    }

    public func appendStatusMessage(_ content: String) {
        messages.append(ChatMessage(role: .assistant, content: content, isComplete: true))
    }

    public func beginStreamingMessage() {
        let id = UUID()
        messages.append(ChatMessage(id: id, role: .assistant, contentBlocks: [], timestamp: Date()))
        currentStreamingMessageId = id
    }

    public func appendTextToCurrentStreamingMessage(_ text: String) {
        guard let id = currentStreamingMessageId,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let existing = messages[index]
        var blocks = existing.contentBlocks
        if case .text(let prev) = blocks.last {
            blocks[blocks.count - 1] = .text(prev + text)
        } else {
            blocks.append(.text(text))
        }
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            contentBlocks: blocks,
            images: existing.images,
            timestamp: existing.timestamp,
            isComplete: false
        )
    }

    public func updateCurrentStreamingBlocks(_ blocks: [AIContentBlock]) {
        guard let id = currentStreamingMessageId,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            contentBlocks: blocks,
            images: existing.images,
            timestamp: existing.timestamp,
            isComplete: false
        )
    }

    public nonisolated func consumeStream(
        _ stream: AsyncStream<AIStreamEvent>,
        messageId: UUID
    ) async {
        let accumulator = StreamAccumulator()
        for await event in stream {
            guard !Task.isCancelled else { break }
            if case .sessionStarted(let id) = event {
                await MainActor.run {
                    self.sessionId = id
                    self.hasStartedSession = true
                }
                continue
            }
            let updatedBlocks = accumulator.apply(event)
            await MainActor.run { [updatedBlocks] in
                guard let index = self.messages.firstIndex(where: { $0.id == messageId }) else { return }
                self.messages[index] = ChatMessage(
                    id: messageId,
                    role: .assistant,
                    contentBlocks: updatedBlocks,
                    timestamp: self.messages[index].timestamp
                )
            }
        }
    }

    public func finalizeCurrentStreamingMessage() {
        guard let id = currentStreamingMessageId,
              let index = messages.firstIndex(where: { $0.id == id }) else {
            currentStreamingMessageId = nil
            return
        }
        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            contentBlocks: existing.contentBlocks,
            images: existing.images,
            timestamp: existing.timestamp,
            isComplete: true
        )
        currentStreamingMessageId = nil
    }

    // MARK: - Session Management

    public func listSessions() async -> [ChatSession] {
        await listSessionsUseCase.run(.init(workingDirectory: workingDirectory))
    }

    public nonisolated func loadSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? {
        getSessionDetailsUseCase.run(.init(sessionId: sessionId, summary: summary, lastModified: lastModified, workingDirectory: workingDirectory))
    }

    public func resumeSession(_ sessionId: String) async {
        self.messages = []
        self.sessionId = sessionId
        self.hasStartedSession = true
        self.state = .loadingHistory

        let messages = await loadSessionMessagesUseCase.run(.init(sessionId: sessionId, workingDirectory: workingDirectory))
        self.messages = messages
        self.state = .idle
    }

    public func setWorkingDirectory(_ path: String) async {
        let resolvedPath = Self.resolveSymlinks(in: path)
        guard resolvedPath != workingDirectory else { return }

        self.workingDirectory = resolvedPath
        self.messages = []
        self.sessionId = nil
        self.hasStartedSession = false

        if settings.resumeLastSession {
            self.state = .loadingHistory
            await resumeLatestSession(workingDirectory: resolvedPath)
            guard self.workingDirectory == resolvedPath else { return }
            self.state = .idle
        }
    }

    // MARK: - Internal

    private nonisolated func sendMessageInternal(_ content: String, images: [ImageAttachment] = []) async {
        let userMessage = ChatMessage(role: .user, content: content, images: images, isComplete: true)
        await MainActor.run {
            messages.append(userMessage)
            state = .processing
        }

        let resumeId = await MainActor.run {
            hasStartedSession ? sessionId : nil
        }
        let workingDir = await MainActor.run { workingDirectory }
        let mcpPath = await MainActor.run { mcpConfigPath }

        let assistantMessageId = UUID()
        let placeholderMessage = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            contentBlocks: [],
            timestamp: Date()
        )

        await MainActor.run {
            messages.append(placeholderMessage)
            currentStreamingMessageId = assistantMessageId
        }

        let options = SendChatMessageUseCase.Options(
            message: content,
            workingDirectory: workingDir,
            sessionId: resumeId,
            images: images,
            mcpConfigPath: mcpPath,
            systemPrompt: systemPrompt
        )

        do {
            let (stream, continuation) = AsyncStream<AIStreamEvent>.makeStream()
            let consumeTask = Task {
                await self.consumeStream(stream, messageId: assistantMessageId)
            }
            await MainActor.run { self.currentConsumeTask = consumeTask }

            let result: SendChatMessageUseCase.Result
            do {
                result = try await sendMessageUseCase.run(options) { @Sendable progress in
                    switch progress {
                    case .streamEvent(let event):
                        continuation.yield(event)
                    case .completed:
                        break
                    }
                }
            } catch {
                continuation.finish()
                consumeTask.cancel()
                throw error
            }
            continuation.finish()
            await consumeTask.value

            await MainActor.run {
                let displayName = providerDisplayName
                if result.exitCode == 0 || result.exitCode == 130 || result.exitCode == 143 {
                    hasStartedSession = true
                    if let newSessionId = result.sessionId {
                        sessionId = newSessionId
                    }
                }

                if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    let existing = messages[index]

                    if result.exitCode != 0 {
                        let errorMessage: String
                        if result.exitCode == 130 || result.exitCode == 143 {
                            errorMessage = "Request interrupted by user"
                        } else {
                            errorMessage = "Error running \(displayName) (exit code \(result.exitCode))\n\(result.stderr)"
                        }
                        messages[index] = ChatMessage(
                            id: assistantMessageId,
                            role: .assistant,
                            content: errorMessage,
                            timestamp: existing.timestamp,
                            isComplete: true
                        )
                    } else {
                        messages[index] = ChatMessage(
                            id: existing.id,
                            role: existing.role,
                            contentBlocks: existing.contentBlocks,
                            images: existing.images,
                            timestamp: existing.timestamp,
                            isComplete: true
                        )
                    }
                }
                state = .idle
            }
        } catch {
            let isCancellation = error is CancellationError
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    let content = isCancellation
                        ? "Request interrupted by user"
                        : "Error: \(error.localizedDescription)"
                    messages[index] = ChatMessage(
                        id: assistantMessageId,
                        role: .assistant,
                        content: content,
                        timestamp: messages[index].timestamp,
                        isComplete: true
                    )
                }
                state = .idle
            }
        }

        await processNextQueuedMessage()
    }

    private nonisolated func processNextQueuedMessage() async {
        let nextMessage = await MainActor.run { messageQueue.first }

        guard let queuedMessage = nextMessage else { return }

        _ = await MainActor.run {
            messageQueue.removeFirst()
        }

        await sendMessageInternal(queuedMessage.content, images: queuedMessage.images)
    }

    private func resumeLatestSession(workingDirectory: String) async {
        guard let result = await resumeLatestSessionUseCase.run(.init(workingDirectory: workingDirectory)) else { return }
        guard self.workingDirectory == workingDirectory else { return }
        self.messages = result.messages
        self.sessionId = result.sessionId
        self.hasStartedSession = true
    }

    // MARK: - Helpers

    private static func resolveSymlinks(in path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return String(cString: buffer)
        }

        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        var resolvedComponents: [String] = []

        for component in components {
            resolvedComponents.append(component)
            let partialPath = resolvedComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
            if realpath(partialPath, &buffer) != nil {
                let resolved = String(cString: buffer)
                resolvedComponents = URL(fileURLWithPath: resolved).pathComponents
            }
        }

        return resolvedComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
    }

    // MARK: - Types

    public enum ModelState {
        case idle
        case loadingHistory
        case processing
    }
}
