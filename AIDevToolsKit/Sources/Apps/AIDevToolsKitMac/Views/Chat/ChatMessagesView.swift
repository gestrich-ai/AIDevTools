import AIOutputSDK
import AppKit
import ChatFeature
import SwiftUI

// MARK: - Display Row

enum ChatDisplayRow: Identifiable {
    case messageHeader(ChatMessage)
    case block(messageId: UUID, offset: Int, block: AIContentBlock)
    case streamingIndicator(messageId: UUID)

    var id: String {
        switch self {
        case .messageHeader(let msg): return "\(msg.id)-header"
        case .block(let msgId, let offset, _): return "\(msgId)-block-\(offset)"
        case .streamingIndicator(let msgId): return "\(msgId)-streaming"
        }
    }
}

// MARK: - Chat Messages View

struct ChatMessagesView: View {
    @Environment(ChatModel.self) var chatModel: ChatModel
    @State private var isNearBottom: Bool = true
    @State private var lastSeenMessageId: UUID?
    @State private var scrollDebounceTask: Task<Void, Never>?
    @State private var showFullOutput: Bool = true
    @State private var collapsedMessageIds: Set<UUID> = []

    private var displayedMessages: [ChatMessage] {
        if showFullOutput {
            return chatModel.messages
        }
        if let last = chatModel.messages.last {
            return [last]
        }
        return []
    }

    private var allRows: [ChatDisplayRow] {
        displayedMessages.flatMap { message -> [ChatDisplayRow] in
            var rows: [ChatDisplayRow] = [.messageHeader(message)]

            let isCollapsed = collapsedMessageIds.contains(message.id)
            let hasText = message.contentBlocks.contains { if case .text = $0 { return true }; return false }

            for (i, block) in message.contentBlocks.enumerated() {
                if isCollapsed && hasText {
                    switch block {
                    case .thinking, .toolUse, .toolResult: continue
                    default: break
                    }
                }
                rows.append(.block(messageId: message.id, offset: i, block: block))
            }

            let isStreaming = message.role == .assistant
                && chatModel.isProcessing
                && chatModel.messages.last?.id == message.id
            if isStreaming && !message.contentBlocks.isEmpty {
                rows.append(.streamingIndicator(messageId: message.id))
            }

            return rows
        }
    }

    private static let latestModeTailLines = 30

    private var displayRows: [ChatDisplayRow] {
        if showFullOutput {
            return allRows
        }
        guard var last = allRows.last else { return [] }
        if case .block(let msgId, let offset, .text(let text)) = last {
            let lines = text.components(separatedBy: .newlines)
            if lines.count > Self.latestModeTailLines {
                let truncated = lines.suffix(Self.latestModeTailLines).joined(separator: "\n")
                last = .block(messageId: msgId, offset: offset, block: .text(truncated))
            }
        }
        return [last]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                List {
                    if chatModel.isLoadingHistory {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Loading conversation...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    } else if chatModel.messages.isEmpty {
                        emptyStateView
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(displayRows) { row in
                            displayRowView(row)
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets(for: row))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .onAppear {
                                isNearBottom = true
                                lastSeenMessageId = chatModel.messages.last?.id
                            }
                            .onDisappear {
                                isNearBottom = false
                            }
                    }
                }
                .listStyle(.plain)
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    if !chatModel.messages.isEmpty {
                        Task {
                            try? await Task.sleep(for: .milliseconds(50))
                            await MainActor.run {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: chatModel.messages.count) { oldCount, newCount in
                    guard newCount > oldCount, isNearBottom else { return }
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = nil
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: chatModel.messages.last?.contentBlocks) { _, _ in
                    guard isNearBottom else { return }
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onDisappear {
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = nil
                }

                VStack(spacing: 8) {
                    if !chatModel.messages.isEmpty {
                        HStack {
                            Spacer()
                            Button(action: { showFullOutput.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showFullOutput ? "text.justify" : "text.line.last.and.arrowtriangle.forward")
                                        .font(.system(size: 11))
                                    Text(showFullOutput ? "Full" : "Latest")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                                )
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 12)
                            .padding(.top, 8)
                        }
                    }

                    if !chatModel.messages.isEmpty && !isNearBottom {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 12, weight: .semibold))

                                let unseenCount = calculateUnseenMessageCount()
                                if unseenCount > 0 {
                                    Text("\(unseenCount)")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            )
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: isNearBottom)
                    }
                }
            }
        }
    }

    // MARK: - Row Rendering

    @ViewBuilder
    private func displayRowView(_ row: ChatDisplayRow) -> some View {
        switch row {
        case .messageHeader(let message):
            ChatMessageHeaderRow(
                message: message,
                providerDisplayName: chatModel.providerDisplayName,
                isCollapsed: collapsedMessageIds.contains(message.id),
                onToggleCollapse: { toggleCollapse(for: message) }
            )
        case .block(_, _, let block):
            ChatBlockRow(block: block)
        case .streamingIndicator:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Streaming...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 44)
            .padding(.vertical, 4)
        }
    }

    private func rowInsets(for row: ChatDisplayRow) -> EdgeInsets {
        switch row {
        case .messageHeader:
            return EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 12)
        case .block, .streamingIndicator:
            return EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12)
        }
    }

    private func toggleCollapse(for message: ChatMessage) {
        if collapsedMessageIds.contains(message.id) {
            collapsedMessageIds.remove(message.id)
        } else {
            collapsedMessageIds.insert(message.id)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("\(chatModel.providerDisplayName) Chat")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text("Chat with \(chatModel.providerDisplayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if chatModel.settings.resumeLastSession {
                    Label("Will resume last session on startup", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if chatModel.settings.verboseMode {
                    Label("Thinking process will be shown", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func calculateUnseenMessageCount() -> Int {
        guard let lastSeenId = lastSeenMessageId else { return 0 }
        guard let lastSeenIndex = chatModel.messages.firstIndex(where: { $0.id == lastSeenId }) else {
            return chatModel.messages.count
        }
        return max(0, chatModel.messages.count - lastSeenIndex - 1)
    }
}
