import AIOutputSDK
import ArgumentParser
import ChatFeature
import DataPathsService
import Foundation
import ProviderRegistryService

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Chat with an AI provider"
    )

    @Option(name: .long, help: "Provider to use for chat (default: first registered)")
    var provider: String?

    @Option(name: .long, help: "System prompt to configure the AI's behavior")
    var systemPrompt: String?

    @Option(name: .long, help: "Working directory (defaults to current directory)")
    var workingDir: String?

    @Option(name: .long, help: "Path to MCP config JSON (default: AIDevTools app config)")
    var mcpConfig: String?

    @Flag(name: .long, help: "Resume the last session")
    var resume: Bool = false

    @Flag(name: .long, help: "List recent sessions and exit")
    var history: Bool = false

    @Option(name: .long, help: "Print messages from a session ID and exit")
    var session: String?

    @Option(name: .long, help: "Cancel the request after N seconds using cooperative cancellation (for testing)")
    var cancelAfter: Int?

    @Argument(help: "Single message to send (omit for interactive mode)")
    var message: String?

    func run() async throws {
        let root = try CLICompositionRoot.create()
        let registry = root.providerRegistry

        let client: any AIClient
        if let provider {
            guard let named = registry.client(named: provider) else {
                print("Unknown provider '\(provider)'. Available: \(registry.providerNames.joined(separator: ", "))")
                throw ExitCode.failure
            }
            client = named
        } else {
            guard let defaultClient = registry.defaultClient else {
                print("No providers registered.")
                throw ExitCode.failure
            }
            client = defaultClient
        }

        let dir = workingDir ?? FileManager.default.currentDirectoryPath

        if history {
            try await listHistory(client: client, workingDirectory: dir)
            return
        }

        if let sessionId = session {
            await printSession(sessionId: sessionId, client: client, workingDirectory: dir)
            return
        }

        let useCase = SendChatMessageUseCase(client: client)
        if let message {
            try await sendMessage(message, workingDirectory: dir, useCase: useCase, client: client)
        } else {
            try await runInteractive(workingDirectory: dir, useCase: useCase, client: client)
        }
    }

    private func sendMessage(
        _ text: String,
        workingDirectory: String,
        useCase: SendChatMessageUseCase,
        client: any AIClient
    ) async throws {
        var sessionId: String?
        if resume {
            let sessions = await client.listSessions(workingDirectory: workingDirectory)
            sessionId = sessions.first?.id
        }

        let options = SendChatMessageUseCase.Options(
            message: text,
            workingDirectory: workingDirectory,
            sessionId: sessionId,
            mcpConfigPath: mcpConfig ?? DataPathsService.mcpConfigFileURL.path,
            systemPrompt: systemPrompt
        )

        if let seconds = cancelAfter {
            let sendTask = Task {
                try await useCase.run(options) { progress in
                    switch progress {
                    case .streamEvent(let event):
                        printStreamEvent(event)
                    case .completed:
                        print()
                    }
                }
            }
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            print("\n[Cancelling after \(seconds)s...]")
            sendTask.cancel()
            _ = try? await sendTask.value
            return
        }

        let result = try await useCase.run(options) { progress in
            switch progress {
            case .streamEvent(let event):
                printStreamEvent(event)
            case .completed:
                print()
            }
        }

        if result.exitCode != 0 {
            throw ExitCode(result.exitCode)
        }
    }

    private func runInteractive(
        workingDirectory: String,
        useCase: SendChatMessageUseCase,
        client: any AIClient
    ) async throws {
        print("\(client.displayName) Chat (type 'exit' or Ctrl-D to quit)")
        print("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}")

        var sessionId: String?

        if resume {
            let sessions = await client.listSessions(workingDirectory: workingDirectory)
            sessionId = sessions.first?.id
            if let sessionId {
                print("Resuming session: \(sessionId)")
            }
        }

        let sessionBox = InteractiveSessionBox()
        let taskBox = InteractiveCancellableTask()

        // Ctrl-C cancels the in-flight request instead of terminating the process.
        // Users exit with Ctrl-D or by typing 'exit'.
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        sigintSource.setEventHandler {
            taskBox.cancel()
            print("\n[Cancelled]")
        }
        sigintSource.resume()
        defer {
            sigintSource.cancel()
            signal(SIGINT, SIG_DFL)
        }

        while true {
            print("\nYou: ", terminator: "")
            fflush(stdout)

            guard let line = readLine(strippingNewline: true) else {
                print()
                break
            }

            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }
            if input.lowercased() == "exit" { break }

            let options = SendChatMessageUseCase.Options(
                message: input,
                workingDirectory: workingDirectory,
                sessionId: sessionId,
                mcpConfigPath: mcpConfig ?? DataPathsService.mcpConfigFileURL.path,
                systemPrompt: systemPrompt
            )

            print("\n\(client.displayName): ", terminator: "")
            fflush(stdout)

            let task = Task {
                try await useCase.run(options) { progress in
                    switch progress {
                    case .streamEvent(let event):
                        switch event {
                        case .sessionStarted(let id):
                            sessionBox.id = id
                        default:
                            printStreamEvent(event)
                        }
                    case .completed:
                        print()
                    }
                }
            }
            taskBox.store(cancel: { task.cancel() })

            do {
                let result = try await task.value
                sessionBox.id = result.sessionId ?? sessionBox.id
            } catch is CancellationError {
                // sessionBox.id already captured from .sessionStarted before cancel
            } catch {
                print("\nError: \(error.localizedDescription)")
            }

            taskBox.clear()
            sessionId = sessionBox.id
        }
    }

    private func printSession(sessionId: String, client: any AIClient, workingDirectory: String) async {
        let messages = await client.loadSessionMessages(sessionId: sessionId, workingDirectory: workingDirectory)

        if messages.isEmpty {
            print("No messages found for session \(sessionId).")
            return
        }

        let separator = String(repeating: "─", count: 60)
        for message in messages {
            switch message.role {
            case .user:
                print("\n\(separator)")
                print("You:")
                print(message.content)
            case .assistant:
                print("\n\(client.displayName):")
                print(message.content)
            case .thinking:
                print("\n[Thinking] \(message.content)")
            }
        }
        print()
    }

    private func listHistory(client: any AIClient, workingDirectory: String) async throws {
        let sessions = await client.listSessions(workingDirectory: workingDirectory)

        if sessions.isEmpty {
            print("No sessions found for \(client.displayName).")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        print("\(client.displayName) sessions:\n")
        for session in sessions {
            let date = dateFormatter.string(from: session.lastModified)
            print("  \(date)  \(session.summary)")
            print("           \(session.id)\n")
        }
    }

    private func printStreamEvent(_ event: AIStreamEvent) {
        switch event {
        case .metrics(let duration, let cost, let turns):
            var parts: [String] = []
            if let duration { parts.append("\(duration)s") }
            if let cost { parts.append("$\(cost)") }
            if let turns { parts.append("\(turns) turns") }
            if !parts.isEmpty {
                print("--- \(parts.joined(separator: " | ")) ---")
            }
        case .sessionStarted:
            break
        case .textDelta(let text):
            print(text, terminator: "")
            fflush(stdout)
        case .thinking(let text):
            print("\n[Thinking] \(text)")
        case .toolResult(_, let summary, _):
            print("  → \(summary)")
        case .toolUse(let name, let detail):
            print("\n[\(name)] \(detail)")
        }
    }
}

private final class InteractiveSessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: String?

    var id: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _id
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _id = newValue
        }
    }
}

private final class InteractiveCancellableTask: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelAction: (() -> Void)?

    func store(cancel: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        cancelAction = cancel
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelAction?()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cancelAction = nil
    }
}
