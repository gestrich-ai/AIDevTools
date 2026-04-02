import Foundation

public final class StreamAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var blocks: [AIContentBlock] = []

    public init() {}

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        blocks = []
    }

    public func apply(_ event: AIStreamEvent) -> [AIContentBlock] {
        lock.lock()
        defer { lock.unlock() }
        switch event {
        case .textDelta(let chunk):
            if case .text(let existing) = blocks.last {
                blocks[blocks.count - 1] = .text(existing + chunk)
            } else {
                blocks.append(.text(chunk))
            }
        case .thinking(let content):
            blocks.append(.thinking(content))
        case .toolUse(let name, let detail):
            blocks.append(.toolUse(name: name, detail: detail))
        case .toolResult(let name, let summary, let isError):
            blocks.append(.toolResult(name: name, summary: summary, isError: isError))
        case .metrics(let duration, let cost, let turns):
            blocks.append(.metrics(duration: duration, cost: cost, turns: turns))
        }
        return blocks
    }
}
