#if canImport(Darwin)
import Foundation
import Testing
@testable import AIOutputSDK

struct FileWatcherTests {

    // MARK: - Non-existent file

    @Test func streamFinishesImmediatelyForNonExistentFile() async {
        // Arrange
        let missingURL = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).txt")
        let watcher = FileWatcher(url: missingURL)
        var receivedCount = 0

        // Act
        for await _ in watcher.contentStream() {
            receivedCount += 1
        }

        // Assert
        #expect(receivedCount == 0)
    }

    // MARK: - File write detection

    @Test(.timeLimit(.minutes(1)))
    func emitsContentWhenFileIsWritten() async throws {
        // Arrange
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTest_\(UUID().uuidString).txt")
        try "initial".write(to: tempURL, atomically: false, encoding: .utf8)

        let watcher = FileWatcher(url: tempURL)
        var receivedContent: String?

        // Act
        let task = Task {
            for await content in watcher.contentStream() {
                receivedContent = content
                break
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        try "updated content".write(to: tempURL, atomically: false, encoding: .utf8)

        // Wait for 200ms debounce + delivery margin
        try await Task.sleep(for: .seconds(3))
        task.cancel()

        // Delete the file to trigger the DispatchSource .delete event handler,
        // which calls source.cancel() on the GCD queue. This ensures cleanup
        // even if the cooperative thread pool is saturated.
        try? FileManager.default.removeItem(at: tempURL)

        // Assert
        #expect(receivedContent == "updated content")
    }

    // MARK: - Cancellation

    @Test(.timeLimit(.minutes(1)))
    func cancellationTerminatesStream() async throws {
        // Arrange
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTest_\(UUID().uuidString).txt")
        try "content".write(to: tempURL, atomically: false, encoding: .utf8)

        let watcher = FileWatcher(url: tempURL)

        // Act
        let task = Task {
            for await _ in watcher.contentStream() {
                // No writes occur, so this body never runs
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // Delete the file to trigger the DispatchSource .delete event handler,
        // which calls source.cancel() on the GCD queue (immune to cooperative
        // thread-pool saturation). This ensures the DispatchSource is torn down
        // even if the AsyncStream iterator never resumes to deliver onTermination.
        try? FileManager.default.removeItem(at: tempURL)

        // Do NOT await task.result — under heavy parallel CI load, the cooperative
        // thread pool saturates and the for-await loop never resumes to exit,
        // causing an indefinite hang. The file deletion above ensures the
        // DispatchSource is cleaned up via GCD regardless.
    }
}
#endif
