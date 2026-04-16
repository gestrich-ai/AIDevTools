@preconcurrency import RepoExplorerCLITools
import Foundation

@preconcurrency public class GitRepo: @unchecked Sendable {
    private let repoPath: String
    private var isCheckedOut: Bool = false
    private let cliService = CLIService.shared
    private let gitBuilder = CommandBuilder().git()
    private let cacheManager: GitBlameCacheManager?
    private var currentRepoCommitHash: String?

    public init(repoPath: String) {
        self.repoPath = repoPath

        // Initialize cache manager
        do {
            self.cacheManager = try GitBlameCacheManager(repoPath: repoPath, cliService: cliService)
            print("✅ Initialized GitBlameCacheManager for repo: \(repoPath)")
        } catch {
            print("⚠️ Failed to initialize GitBlameCacheManager: \(error)")
            self.cacheManager = nil
        }
    }
    
    /// Checkout a specific commit in the repository. This should be called once before running git blame operations.
    public func checkoutCommit(_ commitHash: String) async throws {
        if !isCheckedOut {
            print("🔄 Checking out commit \(commitHash) in \(repoPath)")

            do {
                _ = try await gitBuilder.custom(arguments: ["reset", "--hard", "HEAD"], in: repoPath)
                _ = try await gitBuilder.custom(arguments: ["clean", "-ffdd"], in: repoPath)
                _ = try await gitBuilder.custom(arguments: ["remote", "update"], in: repoPath)
                _ = try await gitBuilder.fetch(remote: "origin", ref: commitHash, in: repoPath)
                _ = try await gitBuilder.checkout("FETCH_HEAD", in: repoPath)

                isCheckedOut = true
                currentRepoCommitHash = commitHash
                print("✅ Successfully checked out commit \(commitHash)")
            } catch {
                // If checkout fails, we'll continue without checking out
                // This allows git blame to work with the current state of the repo
                print("⚠️  Failed to checkout commit \(commitHash): \(error)")
                print("   Continuing with current repository state for git operations")
                isCheckedOut = true // Set to true to avoid retrying

                // Try to get current repo commit hash
                if let cacheManager {
                    currentRepoCommitHash = try? await cacheManager.getCurrentRepoCommitHash()
                }
            }
        }
    }
    
    public func getOwnership(for file: String, line: Int) async throws -> Ownership? {
        let workingDirectory = repoPath
        
        // Transform Bitrise build paths to local relative paths
        let localFilePath = transformBitrisePathToLocal(file)
        
        // Debug logging
//        if file != localFilePath {
//            print("🔄 Transformed path: '\(file)' -> '\(localFilePath)'")
//        }
        
        // Check cache first if available
        if let cacheManager {
            // Get the current commit hash of the file to validate cache
            if let fileCommitHash = try await cacheManager.getCurrentFileCommitHash(filePath: localFilePath) {
                if let cachedOwnership = await cacheManager.getCachedBlame(
                    filePath: localFilePath,
                    line: line,
                    fileCommitHash: fileCommitHash
                ) {
                    print("✅ Cache hit for \(localFilePath):\(line)")
                    return cachedOwnership
                }
            }
        }
        
        // Run git blame from the working directory
        let ownership = try await runGitBlame(file: localFilePath, line: line, workingDirectory: workingDirectory)

        // Cache the result if cache manager is available
        if let ownership {
            if let cacheManager,
               let fileCommitHash = try await cacheManager.getCurrentFileCommitHash(filePath: localFilePath) {
                await cacheManager.cacheBlame(
                    filePath: localFilePath,
                    line: line,
                    fileCommitHash: fileCommitHash,
                    ownership: ownership
                )
                print("💾 Cached blame info for \(localFilePath):\(line)")
            }
            
            return ownership
        }
        
        return nil
    }
    
    private func transformBitrisePathToLocal(_ filePath: String) -> String {
        // Remove common Bitrise build directory prefixes
        let bitrisePatterns = [
            "/Users/vagrant/git/",
            "/Users/vagrant/",  // More general vagrant pattern
            "/tmp/",
            "/var/folders/",
            "/Users/runner/work/",
            "/home/runner/work/",
            "/github/workspace/",
            "/bitrise/src/"
        ]
        
        var cleanedPath = filePath
        
        // Debug logging for path transformation
//        print("🔍 Original path: '\(filePath)'")
        
        for pattern in bitrisePatterns {
            if cleanedPath.hasPrefix(pattern) {
                cleanedPath = String(cleanedPath.dropFirst(pattern.count))
//                print("🔄 Matched pattern '\(pattern)', new path: '\(cleanedPath)'")
                break
            }
        }
        
        // Additional cleanup for common project structures
        let projectPatterns = [
            "ios/",
            "foreflight-ios/",
            "project/"
        ]
        
        for pattern in projectPatterns {
            if cleanedPath.hasPrefix(pattern) {
                cleanedPath = String(cleanedPath.dropFirst(pattern.count))
//                print("🔄 Removed project prefix '\(pattern)', final path: '\(cleanedPath)'")
                break
            }
        }
        
//        print("🎯 Final transformed path: '\(cleanedPath)'")
        return cleanedPath
    }
    
    /// Determines whether a merge queue commit was the only PR in the batch
    /// - Parameter mergeQueueBranch: e.g. "gh-readonly-queue/develop/pr-12345-<40-char-sha>"
    /// - Returns: true if the commit was the only one in the queue, false if it was batched
    /// Determines whether a merge queue commit was the only PR in the batch
    /// - Parameter mergeQueueBranch: e.g. "gh-readonly-queue/develop/pr-12345-<40-char-sha>"
    /// - Returns: true if the commit was the only one in the queue, false if it was batched
    public func isSoloMergeQueueCommit(_ mergeQueueBranch: String) async throws -> Bool {
        // Extract commit hash (last 40 chars)
        guard let commitHashMatch = mergeQueueBranch.range(of: "[a-f0-9]{40}", options: .regularExpression) else {
            throw GitRepoError.gitCommandFailed("Invalid branch format: could not extract commit hash")
        }
        let commitHash = String(mergeQueueBranch[commitHashMatch])

        // Extract base branch (between gh-readonly-queue/ and next /)
        guard let baseBranchMatch = mergeQueueBranch.range(of: #"gh-readonly-queue/([^/]+)/"#, options: .regularExpression),
              let baseBranch = mergeQueueBranch[baseBranchMatch].components(separatedBy: "/").dropFirst().first else {
            throw GitRepoError.gitCommandFailed("Invalid branch format: could not extract base branch")
        }

        print("🔍 Checking solo merge for commit: \(commitHash) on base branch: \(baseBranch)")

        do {
            // Ensure latest remote refs
            _ = try await gitBuilder.custom(arguments: ["remote", "update"], in: repoPath)

            // Ensure latest base branch commits
            _ = try await gitBuilder.fetch(remote: "origin", ref: baseBranch, in: repoPath)

            // Check if commit is ancestor of base branch head
            let result = try await cliService.execute(
                command: "/usr/bin/git",
                arguments: ["merge-base", "--is-ancestor", commitHash, "origin/\(baseBranch)"],
                workingDirectory: repoPath
            )

            if result.exitCode == 0 {
                print("✅ Commit is ancestor of base branch – likely a solo PR")
                return true
            } else {
                print("ℹ️ Commit is not ancestor – likely part of a batch")
                return false
            }
        } catch {
            throw GitRepoError.gitCommandFailed("Failed to analyze merge queue commit: \(error)")
        }
    }
    
    private func runGitBlame(file: String, line: Int, workingDirectory: String) async throws -> Ownership? {
        do {
            let result = try await gitBuilder.blame(file: file, line: line, in: workingDirectory)
            
            guard result.isSuccess else {
                let errorMessage = result.stderr
                
                // Check if this is a "no such path" or "no such file" error - these are expected and should not stop analysis
                let lowercaseError = errorMessage.lowercased()
                if lowercaseError.contains("no such path") ||
                   lowercaseError.contains("no such file") ||
                   lowercaseError.contains("invalid path") ||
                   lowercaseError.contains("does not exist") {
                    print("⚠️  File not found in repo, skipping git blame for: \(file)")
                    return nil
                }
                
                // For other git errors, still throw but make it clear this is unexpected
                print("❌ Unexpected git blame error for \(file): \(errorMessage)")
                throw GitRepoError.gitCommandFailed("Git blame failed: \(errorMessage)")
            }
            
            guard !result.stdout.isEmpty else {
                print("⚠️  Invalid git blame output for \(file), skipping")
                return nil
            }
            
            return parseBlame(output: result.stdout)
        } catch CLIError.executionFailed(_, _, let stderr) {
            // Check if this is an expected error
            let lowercaseError = stderr.lowercased()
            if lowercaseError.contains("no such path") ||
               lowercaseError.contains("no such file") ||
               lowercaseError.contains("invalid path") ||
               lowercaseError.contains("does not exist") {
                print("⚠️  File not found in repo, skipping git blame for: \(file)")
                return nil
            }
            
            print("❌ Unexpected git blame error for \(file): \(stderr)")
            throw GitRepoError.gitCommandFailed("Git blame failed: \(stderr)")
        }
    }
    
    private func parseBlame(output: String) -> Ownership? {
        let lines = output.components(separatedBy: .newlines)
        
        var commitHash: String?
        var authorName: String?
        var authorEmail: String?
        var summary: String?
        var commitDate: String?
        
        for line in lines {
            if commitHash == nil && line.matches(regex: "^[a-f0-9]{40}") {
                commitHash = String(line.prefix(40))
            } else if line.hasPrefix("author ") {
                authorName = String(line.dropFirst("author ".count))
            } else if line.hasPrefix("author-mail ") {
                let email = String(line.dropFirst("author-mail ".count))
                authorEmail = email.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            } else if line.hasPrefix("summary ") {
                summary = String(line.dropFirst("summary ".count))
            } else if line.hasPrefix("author-time ") {
                let timeString = String(line.dropFirst("author-time ".count))
                if let timestamp = TimeInterval(timeString) {
                    let date = Date(timeIntervalSince1970: timestamp)
                    let formatter = ISO8601DateFormatter()
                    commitDate = formatter.string(from: date)
                }
            }
        }
        
        guard let commitHash, !commitHash.isEmpty else {
            return nil
        }

        if let authorName, let authorEmail, let summary {
            let author = GitAuthor(name: authorName, email: authorEmail)
            let confidence = determineConfidence(date: commitDate, summary: summary)
            return Ownership(
                author: author,
                commitHash: commitHash,
                summary: summary,
                commitDate: commitDate,
                confidence: confidence
            )
        }

        return nil
    }
    
    private func determineConfidence(date: String?, summary _: String?) -> String {
        guard let dateString = date, let date = ISO8601DateFormatter().date(from: dateString) else {
            return "low"
        }
        
        let daysSinceCommit = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? Int.max
        
        if daysSinceCommit <= 7 {
            return "high"
        } else if daysSinceCommit <= 30 {
            return "medium"
        } else {
            return "low"
        }
    }
    
    // MARK: - File Search and Method Detection for Test Ownership
    
    /// Search the codebase for files matching a given base filename with Swift and Objective-C extensions
    public func searchCodebase(for baseFileName: String) async throws -> [String] {
        // Try both Swift and Objective-C extensions
        let extensions = ["swift", "m", "mm", "h"]
        var allFiles: [String] = []
        
        for ext in extensions {
            let fileName = "\(baseFileName).\(ext)"
            
            let result = try await gitBuilder.custom(
                arguments: ["ls-files", "**/\(fileName)", fileName],
                in: repoPath
            )
            
            if result.isSuccess && !result.stdout.isEmpty {
                let files = result.stdout.components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                allFiles.append(contentsOf: files)
            }
        }
        
        print("🔍 Found \(allFiles.count) file(s) matching '\(baseFileName).*': \(allFiles)")
        return allFiles
    }
    
    /// Search for files containing the test class name using grep (fallback method)
    public func searchCodebaseForClassName(_ className: String) async throws -> [String] {
        // Use git grep to search for the class name in Swift and Objective-C files
        var files: [String] = []
        
        do {
            let result = try await gitBuilder.custom(
                arguments: ["grep", "-l", "--", className, "*.swift", "*.m", "*.mm", "*.h"],
                in: repoPath
            )
            
            if result.isSuccess && !result.stdout.isEmpty {
                files = result.stdout.components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
        } catch CLIError.executionFailed(_, _, let stderr) {
            // git grep returns non-zero if no matches found, which is expected
            if !stderr.isEmpty && !stderr.contains("no such path") {
                print("⚠️  Git grep warning for '\(className)': \(stderr)")
            }
        }
        
        print("🔍 Found \(files.count) file(s) containing class '\(className)': \(files)")
        return files
    }
    
    /// Find method in specific files and return file paths where the method is found
    public func findMethod(_ methodName: String, in filePaths: [String]) throws -> [String] {
        var filesWithMethod: [String] = []
        
        for filePath in filePaths {
            let fullPath = "\(repoPath)/\(filePath)"
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: fullPath) else {
                print("⚠️  File does not exist: \(fullPath)")
                continue
            }
            
            do {
                let fileContent = try String(contentsOfFile: fullPath)
                
                // Search for method
                let methodFound = fileContent.contains(methodName)
                
                if methodFound {
                    print("✅ Found method '\(methodName)' in: \(filePath)")
                    filesWithMethod.append(filePath)
                } else {
                    print("❌ Method '\(methodName)' not found in: \(filePath)")
                }
            } catch {
                print("⚠️  Failed to read file \(fullPath): \(error)")
            }
        }
        
        return filesWithMethod
    }
    
    /// Find files that contain both a class name and method name
    public func findFilesContainingBoth(className: String, methodName: String, in filePaths: [String]) throws -> [String] {
        var filesWithBoth: [String] = []
        
        for filePath in filePaths {
            let fullPath = "\(repoPath)/\(filePath)"
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: fullPath) else {
                print("⚠️  File does not exist: \(fullPath)")
                continue
            }
            
            do {
                let fileContent = try String(contentsOfFile: fullPath)
                
                // Search for both class name and method name
                let hasClassName = fileContent.contains(className)
                let hasMethodName = fileContent.contains(methodName)
                
                if hasClassName && hasMethodName {
                    print("✅ Found both class '\(className)' and method '\(methodName)' in: \(filePath)")
                    filesWithBoth.append(filePath)
                } else {
                    print("❌ Missing class '\(className)': \(!hasClassName) or method '\(methodName)': \(!hasMethodName) in: \(filePath)")
                }
            } catch {
                print("⚠️  Failed to read file \(fullPath): \(error)")
            }
        }
        
        return filesWithBoth
    }
    
    /// Get git blame information for multiple files at specific line numbers
    public func getGitBlameForFiles(_ filePaths: [String], lineNumber: Int) async throws -> [Ownership] {
        var ownerships: [Ownership] = []
        
        for filePath in filePaths {
            if let ownership = try await getOwnership(for: filePath, line: lineNumber) {
                ownerships.append(ownership)
            }
        }
        
        return ownerships
    }
    
    /// Get last commit information for multiple files (not line-specific)
    public func getLastCommitForFiles(_ filePaths: [String]) async throws -> [Ownership] {
        var ownerships: [Ownership] = []
        
        for filePath in filePaths {
            if let ownership = try await getLastCommitToFile(for: filePath) {
                ownerships.append(ownership)
            }
        }
        
        return ownerships
    }
    
    /// Determine ownership from test metadata using heuristic approach
    public func determineOwnershipFromTestMetadata(testClassName: String?, testMethodName: String?, associatedFileName: String?) async throws -> (ownership: Ownership, filePath: String)? {
        var foundFiles: [String] = []
        
        // Step 1: Try searching by filename if available
        if let fileName = associatedFileName {
            foundFiles = try await searchCodebase(for: fileName)
            print("📁 Found \(foundFiles.count) files by filename search")
        }
        
        // Step 2: Fallback to grep search by class name if filename search failed or no filename
        if foundFiles.isEmpty, let className = testClassName {
            foundFiles = try await searchCodebaseForClassName(className)
            print("🔍 Found \(foundFiles.count) files by class name search")
        }
        
        guard !foundFiles.isEmpty else {
            print("⚠️  No files found for test class '\(testClassName ?? "unknown")'")
            return nil
        }
        
        var targetFiles = foundFiles
        
        // Step 3: If we have a method name, filter files that contain the method
        if let methodName = testMethodName {
            let filesWithMethod = try await findMethod(methodName, in: foundFiles)
            if !filesWithMethod.isEmpty {
                targetFiles = filesWithMethod
                print("🎯 Narrowed down to \(filesWithMethod.count) file(s) containing method '\(methodName)'")
                
                // Step 3.1: If we have both class name and method name, verify both are in the same files
                if let className = testClassName {
                    let filesWithBoth = try await findFilesContainingBoth(className: className, methodName: methodName, in: filesWithMethod)
                    if !filesWithBoth.isEmpty {
                        targetFiles = filesWithBoth
                        print("🎯 Perfect match: Found \(filesWithBoth.count) file(s) containing both class '\(className)' and method '\(methodName)'")
                    }
                }
            }
        }
        
        // Step 4: Get ownership information for the target files
        // Since we don't have line numbers for test metadata searches, use last commit to file
        let ownerships = try await getLastCommitForFiles(targetFiles)
        
        // Step 5: Return the most recent ownership (highest confidence)
        let sortedOwnerships = ownerships.sorted { first, second in
            // Sort by confidence first, then by date
            if first.confidence != second.confidence {
                let confidenceOrder = ["high": 3, "medium": 2, "low": 1]
                return (confidenceOrder[first.confidence] ?? 0) > (confidenceOrder[second.confidence] ?? 0)
            }
            
            // If same confidence, prefer more recent commits
            guard let firstDate = first.commitDate,
                  let secondDate = second.commitDate,
                  let date1 = ISO8601DateFormatter().date(from: firstDate),
                  let date2 = ISO8601DateFormatter().date(from: secondDate) else {
                return false
            }
            
            return date1 > date2
        }
        
        let bestOwnership = sortedOwnerships.first
        if let ownership = bestOwnership {
            print("🎯 Best ownership match: \(ownership.author.name) (\(ownership.confidence) confidence)")
            // Return the ownership and the first file path (they should all be the same file at this point)
            if let filePath = targetFiles.first {
                return (ownership: ownership, filePath: filePath)
            }
        }

        return nil
    }
    
    /// Get ownership information for the last commit that modified a file (not line-specific)
    public func getLastCommitToFile(for file: String) async throws -> Ownership? {
        // Transform Bitrise build paths to local relative paths
        let localFilePath = transformBitrisePathToLocal(file)
        
        // Check cache first if available
        if let cacheManager {
            // Get current repo commit hash
            let repoCommitHash: String
            if let currentHash = currentRepoCommitHash {
                repoCommitHash = currentHash
            } else {
                repoCommitHash = (try? await cacheManager.getCurrentRepoCommitHash()) ?? ""
            }
            
            // Check if we have cached file existence information
            if let fileInfo = await cacheManager.getCachedFileExistence(filePath: localFilePath, repoCommitHash: repoCommitHash) {
                if !fileInfo.exists {
                    print("✅ Cache hit: file \(localFilePath) does not exist")
                    return nil
                }
                
                // If file exists and we have its commit hash, check for cached ownership
                if let fileCommitHash = fileInfo.lastCommitHash {
                    if let cachedOwnership = await cacheManager.getCachedFileCommit(
                        filePath: localFilePath,
                        currentCommitHash: fileCommitHash
                    ) {
                        print("✅ Cache hit for file commit: \(localFilePath)")
                        return cachedOwnership
                    }
                }
            }
        }
        
        // Run git log to get the last commit that modified this file
        let ownership = try await runGitLogForFile(file: localFilePath, workingDirectory: repoPath)
        
        // Cache the result
        if let cacheManager {
            if let ownership {
                // Use cached ownership directly
                let updatedOwnership = ownership
                
                // Cache the ownership
                await cacheManager.cacheFileCommit(
                    filePath: localFilePath,
                    fileCommitHash: ownership.commitHash,
                    ownership: updatedOwnership
                )
                print("💾 Cached file commit info for \(localFilePath)")
                
                // Also cache file existence
                let repoCommitHash: String
                if let currentHash = currentRepoCommitHash {
                    repoCommitHash = currentHash
                } else {
                    repoCommitHash = (try? await cacheManager.getCurrentRepoCommitHash()) ?? ""
                }
                await cacheManager.cacheFileExistence(
                    filePath: localFilePath,
                    repoCommitHash: repoCommitHash,
                    exists: true,
                    lastFileCommitHash: ownership.commitHash
                )
                
                return updatedOwnership
            } else {
                // File doesn't exist - cache this information
                let repoCommitHash: String
                if let currentHash = currentRepoCommitHash {
                    repoCommitHash = currentHash
                } else {
                    repoCommitHash = (try? await cacheManager.getCurrentRepoCommitHash()) ?? ""
                }
                await cacheManager.cacheFileExistence(
                    filePath: localFilePath,
                    repoCommitHash: repoCommitHash,
                    exists: false
                )
                print("💾 Cached non-existence of file \(localFilePath)")
                return nil
            }
        }
        
        // No cache manager - return ownership directly
        if let ownership {
            return ownership
        }
        
        return nil
    }
    
    private func runGitLogForFile(file: String, workingDirectory: String) async throws -> Ownership? {
        do {
            let result = try await gitBuilder.log(
                file: file,
                format: "%H|%an|%ae|%s|%at",
                limit: 1,
                in: workingDirectory
            )
            
            guard result.isSuccess else {
                let errorMessage = result.stderr
                
                // Check if this is a "no such path" or "no such file" error - these are expected and should not stop analysis
                let lowercaseError = errorMessage.lowercased()
                if lowercaseError.contains("no such path") ||
                   lowercaseError.contains("no such file") ||
                   lowercaseError.contains("invalid path") ||
                   lowercaseError.contains("does not exist") {
                    print("⚠️  File not found in repo, skipping git log for: \(file)")
                    return nil
                }
                
                // For other git errors, still throw but make it clear this is unexpected
                print("❌ Unexpected git log error for \(file): \(errorMessage)")
                throw GitRepoError.gitCommandFailed("Git log failed: \(errorMessage)")
            }
            
            guard !result.stdout.isEmpty else {
                print("⚠️  No git history found for \(file), skipping")
                return nil
            }
            
            return parseGitLogOutput(output: result.stdout.trimmingCharacters(in: .newlines))
        } catch CLIError.executionFailed(_, _, let stderr) {
            // Check if this is an expected error
            let lowercaseError = stderr.lowercased()
            if lowercaseError.contains("no such path") ||
               lowercaseError.contains("no such file") ||
               lowercaseError.contains("invalid path") ||
               lowercaseError.contains("does not exist") {
                print("⚠️  File not found in repo, skipping git log for: \(file)")
                return nil
            }
            
            print("❌ Unexpected git log error for \(file): \(stderr)")
            throw GitRepoError.gitCommandFailed("Git log failed: \(stderr)")
        }
    }
    
    private func parseGitLogOutput(output: String) -> Ownership? {
        // Parse format: commitHash|authorName|authorEmail|summary|timestamp
        let components = output.components(separatedBy: "|")
        guard components.count == 5 else {
            print("⚠️  Unexpected git log output format: \(output)")
            return nil
        }
        
        let commitHash = components[0]
        let authorName = components[1]
        let authorEmail = components[2]
        let summary = components[3]
        let timestampString = components[4]
        
        guard !commitHash.isEmpty, !authorName.isEmpty, !authorEmail.isEmpty else {
            return nil
        }
        
        // Convert timestamp to ISO8601 date
        var commitDate: String?
        if let timestamp = TimeInterval(timestampString) {
            let date = Date(timeIntervalSince1970: timestamp)
            let formatter = ISO8601DateFormatter()
            commitDate = formatter.string(from: date)
        }
        
        let author = GitAuthor(name: authorName, email: authorEmail)
        let confidence = determineConfidence(date: commitDate, summary: summary)
        
        return Ownership(
            author: author,
            commitHash: commitHash,
            summary: summary,
            commitDate: commitDate,
            confidence: confidence
        )
    }
    
    /// Get cache statistics
    public func getCacheStatistics() async -> (blameEntries: Int, fileEntries: Int, totalSize: Int64)? {
        guard let cacheManager else { return nil }
        return await cacheManager.getCacheStatistics()
    }
    
    /// Invalidate cache for a specific file
    public func invalidateCache(for filePath: String) async {
        guard let cacheManager else { return }
        let localFilePath = transformBitrisePathToLocal(filePath)
        await cacheManager.invalidateCache(for: localFilePath)
    }
    
    /// Get file content at a specific commit
    public func getFileContent(path: String, at commit: String? = nil) async throws -> String? {
        let localFilePath = transformBitrisePathToLocal(path)
        
        do {
            let result = try await gitBuilder.show(file: localFilePath, at: commit, in: repoPath)
            
            guard result.isSuccess else {
                let errorMessage = result.stderr.lowercased()
                if errorMessage.contains("no such path") ||
                   errorMessage.contains("no such file") ||
                   errorMessage.contains("does not exist") {
                    print("⚠️  File not found in repo: \(localFilePath)")
                    return nil
                }
                throw GitRepoError.gitCommandFailed("Failed to get file content: \(result.stderr)")
            }
            
            return result.stdout
        } catch {
            print("❌ Failed to get file content for \(localFilePath): \(error)")
            throw error
        }
    }
    
    /// Get the diff for a specific commit and file
    public func getCommitDiff(commitHash: String, filePath: String) async throws -> GitDiff? {
        let localFilePath = transformBitrisePathToLocal(filePath)

        print("📝 Getting diff for commit: \(commitHash), file: \(localFilePath)")

        // First, check if the file was changed in this commit
        let service = CLIService.shared
        let changedFilesResult = try await service.execute(
            command: "/usr/bin/git",
            arguments: ["diff-tree", "--no-commit-id", "--name-only", "-r", commitHash],
            workingDirectory: repoPath
        )

        let changedFiles = changedFilesResult.stdout.components(separatedBy: .newlines)
        let fileWasChanged = changedFiles.contains(localFilePath)

        if !fileWasChanged {
            print("ℹ️ File \(localFilePath) was not changed in commit \(commitHash)")
            // Try to get the diff that introduced this file
            let firstCommitResult = try await service.execute(
                command: "/usr/bin/git",
                arguments: ["log", "--follow", "--diff-filter=A", "--format=%H", "--", localFilePath],
                workingDirectory: repoPath
            )

            if !firstCommitResult.stdout.isEmpty {
                let firstCommit = firstCommitResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).last ?? ""
                if !firstCommit.isEmpty {
                    print("📝 Getting original commit diff for file: \(firstCommit)")
                    let originalDiffResult = try await service.execute(
                        command: "/usr/bin/git",
                        arguments: ["show", firstCommit, "--", localFilePath],
                        workingDirectory: repoPath
                    )

                    let analyzer = GitDiffAnalyzer(repoPath: repoPath)
                    let diff = analyzer.parseDiffText(originalDiffResult.stdout, commitHash: firstCommit)
                    print("✅ Got original file creation diff: \(diff.hunks.count) hunks")
                    return diff
                }
            }
        }

        // Use git show to get the diff for this specific commit and file
        let diffResult = try await service.execute(
            command: "/usr/bin/git",
            arguments: ["show", commitHash, "--", localFilePath],
            workingDirectory: repoPath
        )

        guard diffResult.isSuccess else {
            print("⚠️ Git command failed for commit \(commitHash) and file \(localFilePath)")
            print("   Error: \(diffResult.stderr)")
            return nil
        }

        print("📊 Git show output length: \(diffResult.stdout.count) characters")
        if diffResult.stdout.count < 100 {
            print("   Output: \(diffResult.stdout)")
        }

        // Parse the diff output
        let analyzer = GitDiffAnalyzer(repoPath: repoPath)
        let diff = analyzer.parseDiffText(diffResult.stdout, commitHash: commitHash)

        print("✅ Parsed diff: \(diff.hunks.count) hunks, raw content: \(diff.rawContent.count) chars")

        return diff
    }

    /// Get full blame data for a file (all lines with ownership info)
    public func getFullBlameData(for file: String) async throws -> FileBlameData? {
        let localFilePath = transformBitrisePathToLocal(file)
        
        // First get the file content
        guard let fileContent = try await getFileContent(path: localFilePath) else {
            print("⚠️  Could not get file content for: \(localFilePath)")
            return nil
        }
        
        // Run git blame for the entire file
        do {
            let result = try await gitBuilder.blame(file: localFilePath, line: nil, in: repoPath)
            
            guard result.isSuccess else {
                let errorMessage = result.stderr.lowercased()
                if errorMessage.contains("no such path") ||
                   errorMessage.contains("no such file") {
                    print("⚠️  File not found for blame: \(localFilePath)")
                    return nil
                }
                throw GitRepoError.gitCommandFailed("Git blame failed: \(result.stderr)")
            }
            
            // Parse the full blame output
            let sections = parseFullBlame(output: result.stdout, for: localFilePath)
            
            // Sections ready to use

            return FileBlameData(
                filePath: localFilePath,
                fileContent: fileContent,
                sections: sections
            )
        } catch {
            print("❌ Failed to get blame data for \(localFilePath): \(error)")
            throw error
        }
    }
    
    /// Parse git blame output for an entire file
    private func parseFullBlame(output: String, for _: String) -> [BlameSection] {
        var sections: [BlameSection] = []
        let lines = output.components(separatedBy: .newlines)
        
        // Structure to hold blame info for each line
        struct LineBlame {
            let lineNumber: Int
            let commitHash: String
            let author: GitAuthor
            let summary: String
            let commitDate: String?
        }
        
        var lineBlames: [LineBlame] = []
        
        // Current blame info being parsed
        var currentCommitHash: String?
        var currentAuthorName: String?
        var currentAuthorEmail: String?
        var currentSummary: String?
        var currentCommitDate: String?
        var currentLineNumber: Int?
        
        // Parse all line blame information
        for line in lines {
            // Check for commit hash with line numbers
            if let match = line.range(of: "^[a-f0-9]{40}", options: .regularExpression) {
                // Extract commit hash
                currentCommitHash = String(line[match])

                // Extract line number from the blame line
                // With --line-porcelain, format is: hash origLineNumber finalLineNumber [groupLines]
                // But actually the format is: hash origLineNum finalLineNum [numLines]
                // components[0] = hash, components[1] = origLineNum, components[2] = finalLineNum
                let components = line.split(separator: " ")
                if components.count >= 3 {
                    // Note: components[1] is the original line number in that commit
                    // components[2] is the current line number in the file
                    if let finalLine = Int(components[2]) {
                        currentLineNumber = finalLine
                    }
                }
            } else if line.hasPrefix("author ") {
                currentAuthorName = String(line.dropFirst("author ".count))
            } else if line.hasPrefix("author-mail ") {
                let email = String(line.dropFirst("author-mail ".count))
                currentAuthorEmail = email.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            } else if line.hasPrefix("summary ") {
                currentSummary = String(line.dropFirst("summary ".count))
            } else if line.hasPrefix("author-time ") {
                let timeString = String(line.dropFirst("author-time ".count))
                if let timestamp = TimeInterval(timeString) {
                    let date = Date(timeIntervalSince1970: timestamp)
                    let formatter = ISO8601DateFormatter()
                    currentCommitDate = formatter.string(from: date)
                }
            } else if line.hasPrefix("\t") || line == "" {
                // End of blame info for this line - save it
                if let hash = currentCommitHash,
                   let name = currentAuthorName,
                   let email = currentAuthorEmail,
                   let summary = currentSummary,
                   let lineNum = currentLineNumber {
                    let lineBlame = LineBlame(
                        lineNumber: lineNum,
                        commitHash: hash,
                        author: GitAuthor(name: name, email: email),
                        summary: summary,
                        commitDate: currentCommitDate
                    )
                    lineBlames.append(lineBlame)

                    // Reset for next line
                    currentCommitHash = nil
                    currentAuthorName = nil
                    currentAuthorEmail = nil
                    currentSummary = nil
                    currentCommitDate = nil
                    currentLineNumber = nil
                }
            }
        }
        
        // Group consecutive lines with the same commit into sections
        guard !lineBlames.isEmpty else { return sections }

        // Sort by line number to ensure correct order
        lineBlames.sort { $0.lineNumber < $1.lineNumber }
        
        var currentStartLine: Int?
        var currentEndLine: Int?
        var currentOwnership: Ownership?
        var previousSectionCommitHash: String?
        
        for lineBlame in lineBlames {
            // Check if this line continues the current section
            // It must be from the same commit AND be consecutive
            let isConsecutive = currentEndLine != nil && lineBlame.lineNumber == currentEndLine! + 1
            let isSameCommit = lineBlame.commitHash == previousSectionCommitHash

            if !isSameCommit || !isConsecutive {
                // Save previous section if exists
                if let startLine = currentStartLine,
                   let endLine = currentEndLine,
                   let ownership = currentOwnership {
                    sections.append(BlameSection(
                        startLine: startLine,
                        endLine: endLine,
                        ownership: ownership
                    ))
                }

                // Start new section
                let confidence = determineConfidence(date: lineBlame.commitDate, summary: lineBlame.summary)
                currentOwnership = Ownership(
                    author: lineBlame.author,
                    commitHash: lineBlame.commitHash,
                    summary: lineBlame.summary,
                    commitDate: lineBlame.commitDate,
                    confidence: confidence
                )

                currentStartLine = lineBlame.lineNumber
                currentEndLine = lineBlame.lineNumber
                previousSectionCommitHash = lineBlame.commitHash
            } else {
                // Extend current section
                currentEndLine = lineBlame.lineNumber
            }
        }
        
        // Add the last section
        if let startLine = currentStartLine,
           let endLine = currentEndLine,
           let ownership = currentOwnership {
            sections.append(BlameSection(
                startLine: startLine,
                endLine: endLine,
                ownership: ownership
            ))
        }
        
        return sections
    }
}

extension String {
    func matches(regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression) != nil
    }
}
