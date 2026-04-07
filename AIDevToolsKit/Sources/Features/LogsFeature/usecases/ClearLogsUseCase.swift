import Foundation
import LoggingSDK
import UseCaseSDK

public struct ClearLogsUseCase: UseCase {
    public init() {}

    public func execute() {
        // Swallowing intentionally: if the file doesn't exist there is nothing to clear,
        // and truncation/close failures are best-effort — in-memory state is cleared by the caller regardless.
        guard let handle = try? FileHandle(forWritingTo: AIDevToolsLogging.defaultLogFileURL) else { return }
        // Truncate rather than delete so the DispatchSource in LogFileWatcher
        // keeps its file descriptor and streaming resumes for new entries.
        try? handle.truncate(atOffset: 0)
        try? handle.close()
    }
}
