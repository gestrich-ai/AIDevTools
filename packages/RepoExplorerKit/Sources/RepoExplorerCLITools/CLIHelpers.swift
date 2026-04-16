import Foundation

private final class CommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var error = ""
    private var output = ""

    func appendError(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        error += chunk
    }

    func appendOutput(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        output += chunk
    }

    func result(exitCode: Int32) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        return CommandResult(output: output, error: error, exitCode: exitCode)
    }
}

/// Helper functions for CLI operations
public struct CLIHelpers {
    /// Execute a shell command and return its output
    public static func executeShellCommand(_ command: String) async throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        // Get the user's shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        process.executableURL = URL(fileURLWithPath: shell)
        // Use login shell to ensure full environment is loaded
        process.arguments = ["-l", "-c", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Set up environment
        process.environment = setupEnvironment()
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let result = CommandResult(
                    output: output,
                    error: error,
                    exitCode: process.terminationStatus
                )
                
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Execute a process directly (not through shell)
    public static func executeProcess(at path: String, arguments: [String] = []) async throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = setupEnvironment()
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let result = CommandResult(
                    output: output,
                    error: error,
                    exitCode: process.terminationStatus
                )
                
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Set up a proper environment for subprocess execution
    private static func setupEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        
        // Ensure HOME is set
        if environment["HOME"] == nil {
            environment["HOME"] = NSHomeDirectory()
        }
        
        // Set PATH to include common tool locations
        let homeDir = environment["HOME"] ?? NSHomeDirectory()
        let pathComponents = [
            environment["PATH"] ?? "",
            "\(homeDir)/.nvm/versions/node/v22.17.0/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].filter { !$0.isEmpty }
        
        environment["PATH"] = pathComponents.joined(separator: ":")
        
        return environment
    }
    
    /// Execute multiple commands in sequence
    public static func executeCommands(_ commands: [String]) async throws -> [CommandResult] {
        var results: [CommandResult] = []
        
        for command in commands {
            let result = try await executeShellCommand(command)
            results.append(result)
            
            // Stop if a command fails
            if result.exitCode != 0 {
                break
            }
        }
        
        return results
    }
    
    /// Read input from stdin
    public static func readFromStdin() -> String {
        var input = ""
        while let line = readLine() {
            input += line + "\n"
        }
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Output JSON to stdout
    public static func outputJSON<T: Encodable>(_ object: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(object)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
    
    /// Prompt user for input with a message
    public static func prompt(_ message: String) -> String? {
        print(message, terminator: " ")
        return readLine()
    }
    
    /// Prompt user for yes/no confirmation
    public static func confirm(_ message: String) -> Bool {
        print("\(message) (y/n):", terminator: " ")
        let response = readLine()?.lowercased()
        return response == "y" || response == "yes"
    }
    
    // MARK: - Streaming Command Execution
    
    /// Execute a shell command with real-time streaming output
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - workingDirectory: Working directory to execute the command in
    ///   - outputFilter: Optional filter to control which lines are printed (default: print all)
    ///   - pipeStdErrToStdOut: Whether to pipe stderr to stdout (default: true)
    /// - Returns: The complete output after the command finishes
    public static func executeShellCommandStreaming(
        _ command: String,
        workingDirectory: String,
        outputFilter: @escaping @Sendable (String) -> Bool = { _ in true },
        pipeStdErrToStdOut: Bool = true
    ) async throws -> CommandResult {
        // For now, use a simpler approach that avoids concurrency issues
        // We'll create the process and handle output synchronously
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        // Get the user's shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", command]
        process.standardOutput = outputPipe
        process.standardError = pipeStdErrToStdOut ? outputPipe : errorPipe
        process.environment = setupEnvironment()
        
        // Set working directory
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        
        let buffer = CommandOutputBuffer()
        
        // Simple approach: read output periodically while process runs
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    
                    let outputHandle = outputPipe.fileHandleForReading
                    let errorHandle = errorPipe.fileHandleForReading
                    
                    // Read output while process is running
                    while process.isRunning {
                        let outputData = outputHandle.availableData
                        if !outputData.isEmpty, let output = String(data: outputData, encoding: .utf8) {
                            buffer.appendOutput(output)
                            if outputFilter(output) {
                                print(output, terminator: "")
                                fflush(stdout)
                            }
                        }
                        
                        if !pipeStdErrToStdOut {
                            let errorData = errorHandle.availableData
                            if !errorData.isEmpty, let error = String(data: errorData, encoding: .utf8) {
                                buffer.appendError(error)
                                if outputFilter(error) {
                                    print(error, terminator: "")
                                    fflush(stdout)
                                }
                            }
                        }
                        
                        Thread.sleep(forTimeInterval: 0.01) // Brief sleep to avoid busy waiting
                    }
                    
                    // Read any remaining output
                    let finalOutputData = outputHandle.readDataToEndOfFile()
                    if let finalOutput = String(data: finalOutputData, encoding: .utf8), !finalOutput.isEmpty {
                        buffer.appendOutput(finalOutput)
                        if outputFilter(finalOutput) {
                            print(finalOutput, terminator: "")
                            fflush(stdout)
                        }
                    }
                    
                    if !pipeStdErrToStdOut {
                        let finalErrorData = errorHandle.readDataToEndOfFile()
                        if let finalError = String(data: finalErrorData, encoding: .utf8), !finalError.isEmpty {
                            buffer.appendError(finalError)
                            if outputFilter(finalError) {
                                print(finalError, terminator: "")
                                fflush(stdout)
                            }
                        }
                    }
                    
                    process.waitUntilExit()
                    
                    let result = buffer.result(exitCode: process.terminationStatus)
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute a process directly with real-time streaming output
    /// - Parameters:
    ///   - path: Path to the executable
    ///   - arguments: Arguments to pass to the executable
    ///   - outputFilter: Optional filter to control which lines are printed
    ///   - pipeStdErrToStdOut: Whether to pipe stderr to stdout
    /// - Returns: The complete output after the process finishes
    public static func executeProcessStreaming(
        at path: String,
        arguments: [String] = [],
        outputFilter: @escaping @Sendable (String) -> Bool = { _ in true },
        pipeStdErrToStdOut: Bool = true
    ) async throws -> CommandResult {
        // Use simpler approach similar to shell command streaming
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = pipeStdErrToStdOut ? outputPipe : errorPipe
        process.environment = setupEnvironment()
        
        let buffer = CommandOutputBuffer()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    
                    let outputHandle = outputPipe.fileHandleForReading
                    let errorHandle = errorPipe.fileHandleForReading
                    
                    // Read output while process is running
                    while process.isRunning {
                        let outputData = outputHandle.availableData
                        if !outputData.isEmpty, let output = String(data: outputData, encoding: .utf8) {
                            buffer.appendOutput(output)
                            if outputFilter(output) {
                                print(output, terminator: "")
                                fflush(stdout)
                            }
                        }
                        
                        if !pipeStdErrToStdOut {
                            let errorData = errorHandle.availableData
                            if !errorData.isEmpty, let error = String(data: errorData, encoding: .utf8) {
                                buffer.appendError(error)
                                if outputFilter(error) {
                                    print(error, terminator: "")
                                    fflush(stdout)
                                }
                            }
                        }
                        
                        Thread.sleep(forTimeInterval: 0.01) // Brief sleep to avoid busy waiting
                    }
                    
                    // Read any remaining output
                    let finalOutputData = outputHandle.readDataToEndOfFile()
                    if let finalOutput = String(data: finalOutputData, encoding: .utf8), !finalOutput.isEmpty {
                        buffer.appendOutput(finalOutput)
                        if outputFilter(finalOutput) {
                            print(finalOutput, terminator: "")
                            fflush(stdout)
                        }
                    }
                    
                    if !pipeStdErrToStdOut {
                        let finalErrorData = errorHandle.readDataToEndOfFile()
                        if let finalError = String(data: finalErrorData, encoding: .utf8), !finalError.isEmpty {
                            buffer.appendError(finalError)
                            if outputFilter(finalError) {
                                print(finalError, terminator: "")
                                fflush(stdout)
                            }
                        }
                    }
                    
                    process.waitUntilExit()
                    
                    let result = buffer.result(exitCode: process.terminationStatus)
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
