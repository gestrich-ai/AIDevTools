import Foundation
import RunCommandFeature

@MainActor @Observable
final class RunCommandModel {
    enum State {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    private(set) var state: State = .idle

    private var runTask: Task<Void, Never>?

    func run(_ command: String, in directory: URL) {
        runTask?.cancel()
        state = .running
        runTask = Task {
            do {
                _ = try await ExecuteRunCommandUseCase().run(command: command, in: directory)
                state = .succeeded
                // Swallowing CancellationError intentionally — visual feedback timer, cancellation resets state anyway.
                try? await Task.sleep(for: .seconds(2))
                if case .succeeded = state { state = .idle }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func reset() {
        runTask?.cancel()
        state = .idle
    }
}
