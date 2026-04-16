import Foundation

// Helper class to pass result in closure
private final class ResultBox: @unchecked Sendable {
    var result: CommandResult?
}

// Helper class to track the last tool_use_id
public final class LastToolUseIdBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.refactor.lasttooluseid")
    private var _value: String?
    private var _lastMessageUuid: String?

    public init() {}

    public var value: String? {
        queue.sync { _value }
    }

    public var lastMessageUuid: String? {
        queue.sync { _lastMessageUuid }
    }

    public func update(toolUseId: String?, messageUuid: String?) {
        queue.sync {
            if let toolUseId {
                _value = toolUseId
            }
            if let messageUuid {
                _lastMessageUuid = messageUuid
            }
        }
    }
}

// Wrapper to allow cancelling a running process
public final class CancellableTask: @unchecked Sendable {
    private let process: Process
    public let lastToolUseIdBox: LastToolUseIdBox
    private var outputHandler: ((String) -> Void)?

    init(process: Process, lastToolUseIdBox: LastToolUseIdBox, outputHandler: ((String) -> Void)? = nil) {
        self.process = process
        self.lastToolUseIdBox = lastToolUseIdBox
        self.outputHandler = outputHandler
    }

    public func setOutputHandler(_ handler: @escaping (String) -> Void) {
        self.outputHandler = handler
    }

    public func handleOutput(_ output: String) {
        outputHandler?(output)
    }

    /// Get the last tool_use_id that was called (if any)
    public var lastToolUseId: String? {
        lastToolUseIdBox.value
    }

    /// Get the last message UUID (parentUuid for interrupt message)
    public var lastMessageUuid: String? {
        lastToolUseIdBox.lastMessageUuid
    }

    /// Gracefully interrupt the process by sending SIGINT (like Ctrl+C)
    public func interrupt() {
        print("⚠️ CancellableTask: interrupt() called (SIGINT), process.isRunning = \(process.isRunning)")
        guard process.isRunning else {
            print("⚠️ CancellableTask: Process not running, nothing to interrupt")
            return
        }

        print("⚠️ CancellableTask: Sending SIGINT (Ctrl+C signal)...")
        process.interrupt()  // Send SIGINT (exit code 130 = 128 + 2)
        print("⚠️ CancellableTask: SIGINT sent")
    }

    /// Forcefully terminate the process (SIGTERM)
    public func cancel() {
        print("🛑 CancellableTask: cancel() called (force), process.isRunning = \(process.isRunning)")
        if process.isRunning {
            print("🛑 CancellableTask: Terminating process...")
            process.terminate()
            print("🛑 CancellableTask: Process terminated")
        } else {
            print("🛑 CancellableTask: Process not running, nothing to terminate")
        }
    }

    public var isRunning: Bool {
        process.isRunning
    }
}

public final class CommandLineRunner: @unchecked Sendable {
    public init() {}
    
    /// Run command synchronously and return output
    public func runSync(
        program: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) -> CommandResult {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox()
        
        runAsync(
            program: program,
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment,
            outputHandler: nil
        ) { commandResult in
            resultBox.result = commandResult
            semaphore.signal()
        }
        
        semaphore.wait()
        return resultBox.result ?? CommandResult(output: "", error: "", exitCode: -1)
    }
    
    /// Run command asynchronously with streaming output
    /// Returns a CancellableTask that can be used to terminate the process
    @discardableResult
    public func runAsync(
        program: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        outputHandler: ((String) -> Void)? = nil,
        completion: @escaping @Sendable (CommandResult) -> Void
    ) -> CancellableTask {
        let task = Process()
        let lastToolUseIdBox = LastToolUseIdBox()
        
        // Set up environment with proper PATH
        var env = ProcessInfo.processInfo.environment
        
        // Add common paths for Homebrew, git-lfs, and other tools
        let additionalPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Users/bill/.nvm/versions/node/v22.17.0/bin"  // Add nvm/node path for claude
        ]
        
        if let currentPath = env["PATH"] {
            // Prepend additional paths to ensure they're found first
            env["PATH"] = (additionalPaths + [currentPath]).joined(separator: ":")
        } else {
            env["PATH"] = additionalPaths.joined(separator: ":")
        }
        
        // Merge with any provided environment variables
        if let environment {
            for (key, value) in environment {
                env[key] = value
            }
        }
        
        task.environment = env
        
        // Set working directory
        if let currentDirectory {
            task.currentDirectoryURL = currentDirectory
        }
        
        // Set up command
        task.launchPath = "/usr/bin/env"
        task.arguments = [program] + arguments

        // Use a class to handle mutable state in a thread-safe way
        let outputHandler = OutputHandler(outputHandler: outputHandler)

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let outputHandle = outputPipe.fileHandleForReading
        
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                print("📦 CommandLineRunner: readabilityHandler called with \(data.count) bytes, \(line.count) chars")
                outputHandler.appendOutput(line)
            }
        }
        
        let errorPipe = Pipe()
        task.standardError = errorPipe
        let errorHandle = errorPipe.fileHandleForReading
        
        errorHandle.readabilityHandler = { handle in
            guard let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty else {
                return
            }
            outputHandler.appendError(line)
        }
        
        task.terminationHandler = { process in
            outputHandle.closeFile()
            errorHandle.closeFile()

            let result = outputHandler.getResult(exitCode: process.terminationStatus)
            completion(result)
        }
        task.launch()

        return CancellableTask(process: task, lastToolUseIdBox: lastToolUseIdBox)
    }
    
    /// Run Git command in a specific repository
    public func runGitCommand(
        arguments: [String],
        repoPath: String,
        outputHandler _: ((String) -> Void)? = nil
    ) -> CommandResult {
        let repoURL = URL(fileURLWithPath: repoPath)
        return runSync(
            program: "git",
            arguments: arguments,
            currentDirectory: repoURL
        )
    }
    
    /// Run Git command asynchronously with streaming output
    public func runGitCommandAsync(
        arguments: [String],
        repoPath: String,
        outputHandler: ((String) -> Void)? = nil,
        completion: @escaping @Sendable (CommandResult) -> Void
    ) {
        let repoURL = URL(fileURLWithPath: repoPath)
        runAsync(
            program: "git",
            arguments: arguments,
            currentDirectory: repoURL,
            outputHandler: outputHandler,
            completion: completion
        )
    }
}

// Thread-safe output handler
private final class OutputHandler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.refactor.outputhandler")
    private var outputString = ""
    private var errorString = ""
    private let outputCallback: ((String) -> Void)?
    
    init(outputHandler: ((String) -> Void)?) {
        self.outputCallback = outputHandler
    }
    
    func appendOutput(_ text: String) {
        queue.sync {
            outputString += text
            outputCallback?(text)
        }
    }
    
    func appendError(_ text: String) {
        queue.sync {
            errorString += text
        }
    }
    
    func getResult(exitCode: Int32) -> CommandResult {
        return queue.sync {
            CommandResult(
                output: outputString,
                error: errorString,
                exitCode: exitCode
            )
        }
    }
}
