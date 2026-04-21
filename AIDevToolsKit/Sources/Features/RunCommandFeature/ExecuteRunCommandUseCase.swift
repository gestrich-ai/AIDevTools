import Foundation
import UseCaseSDK

public struct ExecuteRunCommandUseCase: UseCase {
    public init() {}

    public func run(command: String, in directory: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = directory
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            var stdoutData = Data()
            var stderrData = Data()
            let group = DispatchGroup()

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                group.leave()
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let output = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: RunCommandError.executionFailed(
                        exitCode: process.terminationStatus,
                        output: output.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
        }
    }
}
