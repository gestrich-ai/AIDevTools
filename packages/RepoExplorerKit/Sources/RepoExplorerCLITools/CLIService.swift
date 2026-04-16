import Foundation

/// A service for executing command-line operations with async/await support
public actor CLIService {
    /// Shared instance for convenience
    public static let shared = CLIService()
    
    /// Pre-computed environment with common paths
    private let defaultEnvironment: [String: String]
    
    /// Cache for executable paths
    private var executableCache: [String: String] = [:]
    
    public init() {
        // Pre-compute environment with git paths
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        let brewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let pathComponents = currentPath.components(separatedBy: ":")
        
        // Add brew paths if they're not already in PATH
        var updatedPathComponents = pathComponents
        for brewPath in brewPaths {
            if !pathComponents.contains(brewPath) {
                updatedPathComponents.insert(brewPath, at: 0)
            }
        }
        
        environment["PATH"] = updatedPathComponents.joined(separator: ":")
        self.defaultEnvironment = environment
    }
    
    /// Format a command as a shell-executable string
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Arguments to pass to the command
    ///   - environment: Environment variables to set
    /// - Returns: Formatted command string that can be copy-pasted into a terminal
    public nonisolated func formatCommand(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) -> String {
        var parts: [String] = []

        // Add environment variables
        if let environment {
            for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
                parts.append("export \(key)='\(value)' &&")
            }
        }

        // Add command
        parts.append(command)

        // Add arguments (properly quoted)
        for arg in arguments {
            if arg.contains(" ") || arg.contains("'") || arg.contains("\"") {
                // Escape single quotes and wrap in single quotes
                let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("'\(escaped)'")
            } else {
                parts.append(arg)
            }
        }

        return parts.joined(separator: " ")
    }

    /// Execute a command with full control over the execution environment
    /// - Parameters:
    ///   - command: The command to execute (can be a path or command name)
    ///   - arguments: Arguments to pass to the command
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables (merged with defaults)
    ///   - timeout: Optional timeout in seconds
    ///   - printCommand: If true, prints the formatted command before execution
    /// - Returns: ExecutionResult containing exit code, stdout, and stderr
    public func execute(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        printCommand: Bool = false
    ) async throws -> ExecutionResult {
        let startTime = Date()

        // Resolve command path
        let resolvedCommand = try resolveCommand(command)

        // Merge environments
        var processEnvironment = defaultEnvironment
        if let customEnvironment = environment {
            for (key, value) in customEnvironment {
                processEnvironment[key] = value
            }
        }

        // Print command if requested
        if printCommand {
            let formattedCommand = formatCommand(
                command: resolvedCommand,
                arguments: arguments,
                environment: environment
            )
            print("🔧 Command: \(formattedCommand)")
        }
        return try await executeProcess(
            command: resolvedCommand,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: processEnvironment,
            timeout: timeout,
            startTime: startTime
        )
    }
    
    /// Convenience method for simple command execution
    /// - Parameters:
    ///   - command: Command string (can include arguments)
    ///   - directory: Working directory
    /// - Returns: The stdout output as a string
    public func run(
        _ command: String,
        in directory: String? = nil
    ) async throws -> String {
        let components = command.components(separatedBy: " ")
        guard !components.isEmpty else {
            throw CLIError.invalidCommand("Empty command")
        }
        
        let executable = components[0]
        let arguments = Array(components.dropFirst())
        
        let result = try await execute(
            command: executable,
            arguments: arguments,
            workingDirectory: directory
        )
        
        if result.exitCode != 0 {
            throw CLIError.executionFailed(
                command: command,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        
        return result.stdout
    }
    
    /// Execute a command and stream its output
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Arguments to pass to the command
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables
    /// - Returns: AsyncStream of output lines
    public func stream(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) -> AsyncStream<StreamOutput> {
        AsyncStream { continuation in
            Task {
                do {
                    let resolvedCommand = try resolveCommand(command)
                    
                    var processEnvironment = defaultEnvironment
                    if let customEnvironment = environment {
                        for (key, value) in customEnvironment {
                            processEnvironment[key] = value
                        }
                    }
                    
                    try streamProcess(
                        command: resolvedCommand,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        environment: processEnvironment,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func resolveCommand(_ command: String) throws -> String {
        // If it's already an absolute path, use it
        if command.starts(with: "/") {
            guard FileManager.default.fileExists(atPath: command) else {
                throw CLIError.commandNotFound(command)
            }
            return command
        }
        
        // Check cache
        if let cached = executableCache[command] {
            return cached
        }
        
        // Common direct paths
        let commonPaths = [
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                executableCache[command] = path
                return path
            }
        }
        
        // Fall back to using 'which' command
        let which = Process()
        which.launchPath = "/usr/bin/which"
        which.arguments = [command]
        which.environment = defaultEnvironment
        
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        
        try which.run()
        which.waitUntilExit()
        
        if which.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                executableCache[command] = path
                return path
            }
        }
        
        throw CLIError.commandNotFound(command)
    }
    
    private func executeProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        startTime: Date
    ) async throws -> ExecutionResult {
        try self.executeProcessInternal(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
            startTime: startTime
        )
    }

    private func executeProcessInternal(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        startTime: Date
    ) throws -> ExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        var timeoutTask: Task<Void, Never>?
        if let timeout {
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        timeoutTask?.cancel()

        let stdoutData = outputHandle.readDataToEndOfFile()
        let stderrData = errorHandle.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let duration = Date().timeIntervalSince(startTime)

        if let timeout, duration >= timeout && process.terminationStatus != 0 {
            throw CLIError.timeout(command: "\(command) \(arguments.joined(separator: " "))", duration: timeout)
        }

        return ExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            duration: duration
        )
    }
    
    private func streamProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        continuation: AsyncStream<StreamOutput>.Continuation
    ) throws {
        let process = Process()
        process.launchPath = command
        process.arguments = arguments
        process.environment = environment
        
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Set up output handling
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                continuation.yield(.stdout(line))
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                continuation.yield(.stderr(line))
            }
        }
        
        try process.run()
        process.waitUntilExit()
        
        // Clean up
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        
        continuation.yield(.exit(process.terminationStatus))
        continuation.finish()
    }
}

/// Output type for streaming commands
public enum StreamOutput: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
    case error(Error)
}
