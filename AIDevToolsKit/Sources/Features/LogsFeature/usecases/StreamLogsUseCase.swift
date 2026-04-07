import LoggingSDK
import UseCaseSDK

public struct StreamLogsUseCase: StreamingUseCase {
    public init() {}

    /// Returns an async stream that first yields all existing log entries, then yields
    /// new entries as they are appended to the log file.
    public func stream() -> AsyncThrowingStream<[LogEntry], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let existing = try LogReaderService().readAll()
                    continuation.yield(existing)
                    for await newEntries in LogFileWatcher().stream() {
                        continuation.yield(newEntries)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
