import Foundation

#if canImport(CoreServices)
import CoreServices

private final class CallbackContext {
    let monitor: FileSystemMonitor

    init(monitor: FileSystemMonitor) {
        self.monitor = monitor
    }
}

public actor FileSystemMonitor {
    private let debounceIntervalNanoseconds: UInt64 = 2_000_000_000
    private let onChange: @Sendable ([String]) async -> Void
    private var callbackContext: CallbackContext?
    private var debounceTask: Task<Void, Never>?
    private var eventStream: FSEventStreamRef?
    private var isMonitoring = false
    private var pendingChanges: Set<String> = []

    public init(onChange: @escaping @Sendable ([String]) async -> Void) {
        self.onChange = onChange
    }

    public func startMonitoring(path: String) {
        guard !isMonitoring else {
            return
        }

        FileTreeLoggers.monitor.debug("Starting FSEvents monitoring", metadata: ["path": .string(path)])

        let context = CallbackContext(monitor: self)
        callbackContext = context

        let pathsToWatch = [path as CFString] as CFArray
        var streamContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(context).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else {
                    return
                }

                Unmanaged<CallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, contextInfo, numEvents, eventPaths, eventFlags, _ in
                guard let contextInfo else {
                    return
                }

                let context = Unmanaged<CallbackContext>.fromOpaque(contextInfo).takeUnretainedValue()
                let monitor = context.monitor
                let pathsPointer = eventPaths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>?.self)
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

                var paths: [String] = []
                for index in 0..<numEvents {
                    if let cString = pathsPointer[index] {
                        paths.append(String(cString: cString))
                    }
                }

                Task {
                    await monitor.handleFileSystemEvents(paths: paths, flags: flags)
                }
            },
            &streamContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        ) else {
            FileTreeLoggers.monitor.error("Failed to create FSEventStream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

        if FSEventStreamStart(stream) {
            eventStream = stream
            isMonitoring = true
            FileTreeLoggers.monitor.debug("FSEvents monitoring started")
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            FileTreeLoggers.monitor.error("Failed to start FSEventStream")
        }
    }

    public func stopMonitoring() {
        guard isMonitoring, let stream = eventStream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        callbackContext = nil
        debounceTask?.cancel()
        debounceTask = nil
        eventStream = nil
        isMonitoring = false
        pendingChanges.removeAll()
    }

    private func flushPendingChanges() async {
        guard !pendingChanges.isEmpty else {
            return
        }

        let changes = Array(pendingChanges)
        pendingChanges.removeAll()
        await onChange(changes)
    }

    private func handleFileSystemEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        var changedPaths: Set<String> = []

        for (index, path) in paths.enumerated() {
            let flag = flags[index]
            if path.contains("/.git/") || path.hasSuffix("/.git") {
                continue
            }

            if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
            {
                let directoryPath = (path as NSString).deletingLastPathComponent
                changedPaths.insert(directoryPath)

                if flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 {
                    changedPaths.insert(path)
                }
            }
        }

        guard !changedPaths.isEmpty else {
            return
        }

        pendingChanges.formUnion(changedPaths)
        debounceTask?.cancel()
        let debounceIntervalNanoseconds = self.debounceIntervalNanoseconds
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceIntervalNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await self?.flushPendingChanges()
        }
    }
}
#else
public actor FileSystemMonitor {
    private let onChange: @Sendable ([String]) async -> Void

    public init(onChange: @escaping @Sendable ([String]) async -> Void) {
        self.onChange = onChange
    }

    public func startMonitoring(path: String) {
        FileTreeLoggers.monitor.debug(
            "File system monitoring is unavailable on this platform",
            metadata: ["path": .string(path)]
        )
    }

    public func stopMonitoring() {}
}
#endif
