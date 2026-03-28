import Foundation

public struct AIRunHandle: Sendable {
    public let events: AsyncStream<AIStreamEvent>
    public let result: @Sendable () async throws -> AIClientResult

    public init(events: AsyncStream<AIStreamEvent>, result: @escaping @Sendable () async throws -> AIClientResult) {
        self.events = events
        self.result = result
    }
}

public struct AIStructuredRunHandle<T: Decodable & Sendable>: Sendable {
    public let events: AsyncStream<AIStreamEvent>
    public let result: @Sendable () async throws -> AIStructuredResult<T>

    public init(events: AsyncStream<AIStreamEvent>, result: @escaping @Sendable () async throws -> AIStructuredResult<T>) {
        self.events = events
        self.result = result
    }
}

actor ResultHolder<T: Sendable> {
    private var storedResult: Result<T, Error>?
    private var continuations: [CheckedContinuation<T, Error>] = []

    var value: T {
        get async throws {
            if let storedResult {
                return try storedResult.get()
            }
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }
    }

    func succeed(_ value: T) {
        storedResult = .success(value)
        for continuation in continuations {
            continuation.resume(returning: value)
        }
        continuations.removeAll()
    }

    func fail(_ error: Error) {
        storedResult = .failure(error)
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        continuations.removeAll()
    }
}
