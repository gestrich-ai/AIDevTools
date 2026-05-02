#if canImport(Darwin)
import Foundation

public struct FileWatcher: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Returns an AsyncStream that emits the file's content whenever it changes on disk.
    /// Uses DispatchSource.makeFileSystemObjectSource to watch for writes.
    /// Debounces rapid changes by 200ms to avoid flooding during multi-write operations.
    ///
    /// The returned stream also holds a `SourceGuard` that cancels the DispatchSource
    /// in its `deinit`. This ensures cleanup even when the Swift cooperative thread pool
    /// is saturated and `onTermination` delivery is delayed (which would otherwise keep
    /// the DispatchSource alive indefinitely, preventing process exit).
    public func contentStream() -> AsyncStream<String> {
        let url = self.url
        return AsyncStream { continuation in
            let fileDescriptor = open(url.path, O_EVTONLY)
            guard fileDescriptor >= 0 else {
                continuation.finish()
                return
            }

            let queue = DispatchQueue(label: "FileWatcher.\(url.lastPathComponent)")
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: .write,
                queue: queue
            )

            let debounce = DebounceState()

            // Guard ensures DispatchSource cleanup via deinit when the continuation
            // and all closures are released — even if onTermination never fires.
            let guard_ = SourceGuard(source: source, debounce: debounce)

            source.setEventHandler { [guard_] in
                _ = guard_  // prevent premature deallocation
                debounce.task?.cancel()
                debounce.task = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        continuation.yield(content)
                    }
                }
            }

            source.setCancelHandler {
                close(fileDescriptor)
            }

            continuation.onTermination = { [guard_] _ in
                guard_.cancel()
            }

            source.resume()
        }
    }
}

/// Ensures the DispatchSource is cancelled when all references are dropped.
/// This is critical for parallel CI: when the cooperative thread pool is saturated,
/// AsyncStream's onTermination may never fire (it requires the iterator to be polled).
/// The deinit runs on whatever thread drops the last reference — typically a GCD thread,
/// not subject to cooperative pool starvation.
private final class SourceGuard {
    private let source: DispatchSourceFileSystemObject
    private let debounce: DebounceState

    init(source: DispatchSourceFileSystemObject, debounce: DebounceState) {
        self.source = source
        self.debounce = debounce
    }

    func cancel() {
        debounce.task?.cancel()
        source.cancel()
    }

    deinit {
        cancel()
    }
}

private final class DebounceState {
    var task: Task<Void, Never>?
}
#endif
