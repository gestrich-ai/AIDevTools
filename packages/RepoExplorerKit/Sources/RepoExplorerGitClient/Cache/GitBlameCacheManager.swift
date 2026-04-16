import RepoExplorerCLITools
import Foundation
import SwiftData

/// Manages the SwiftData cache for Git blame operations
public actor GitBlameCacheManager {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let cliService: CLIService
    private let repoPath: String
    
    /// Maximum age for cache entries (30 days)
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60
    
    /// Maximum number of entries to keep
    private let maxEntries = 10_000
    
    public init(repoPath: String, cliService: CLIService = .shared) throws {
        self.repoPath = repoPath
        self.cliService = cliService
        
        do {
            let schema = Schema([
                GitBlameCache.self,
                FileCommitCache.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            
            self.modelContext = ModelContext(modelContainer)
            self.modelContext.autosaveEnabled = true
        } catch {
            throw GitBlameCacheError.containerInitializationFailed(error)
        }
    }
    
    // MARK: - Blame Cache Operations
    
    /// Get cached blame information for a specific file and line
    public func getCachedBlame(filePath: String, line: Int, fileCommitHash: String) -> Ownership? {
        let id = GitBlameCache.makeId(filePath: filePath, line: line, commitHash: fileCommitHash)
        
        let descriptor = FetchDescriptor<GitBlameCache>(
            predicate: #Predicate { $0.id == id }
        )
        
        do {
            let results = try modelContext.fetch(descriptor)
            if let cacheEntry = results.first {
                cacheEntry.touch()
                try? modelContext.save()
                return cacheEntry.toOwnership()
            }
        } catch {
            print("⚠️ Failed to fetch blame cache: \(error)")
        }
        
        return nil
    }
    
    /// Cache blame information for a specific file and line
    public func cacheBlame(
        filePath: String,
        line: Int,
        fileCommitHash: String,
        ownership: Ownership
    ) {
        let cacheEntry = GitBlameCache(
            filePath: filePath,
            line: line,
            fileCommitHash: fileCommitHash,
            authorName: ownership.author.name,
            authorEmail: ownership.author.email,
            blameCommitHash: ownership.commitHash,
            blameCommitMessage: ownership.summary,
            blameCommitDate: ownership.commitDate.flatMap { ISO8601DateFormatter().date(from: $0) },
            confidence: ownership.confidence,
            isFileCommit: false
        )
        
        modelContext.insert(cacheEntry)
        
        do {
            try modelContext.save()
        } catch {
            print("⚠️ Failed to save blame cache: \(error)")
        }
        
        // Cleanup old entries in background
        Task.detached { [weak self] in
            await self?.cleanupIfNeeded()
        }
    }
    
    /// Get cached file-level commit information
    public func getCachedFileCommit(filePath: String, currentCommitHash: String) -> Ownership? {
        // For file commits, we use line 0 as a convention
        return getCachedBlame(filePath: filePath, line: 0, fileCommitHash: currentCommitHash)
    }
    
    /// Cache file-level commit information
    public func cacheFileCommit(
        filePath: String,
        fileCommitHash: String,
        ownership: Ownership?
    ) {
        guard let ownership else {
            // Cache that the file doesn't exist
            cacheFileExistence(filePath: filePath, repoCommitHash: fileCommitHash, exists: false)
            return
        }
        
        let cacheEntry = GitBlameCache(
            filePath: filePath,
            line: 0, // Convention for file-level commits
            fileCommitHash: fileCommitHash,
            authorName: ownership.author.name,
            authorEmail: ownership.author.email,
            blameCommitHash: ownership.commitHash,
            blameCommitMessage: ownership.summary,
            blameCommitDate: ownership.commitDate.flatMap { ISO8601DateFormatter().date(from: $0) },
            confidence: ownership.confidence,
            isFileCommit: true
        )
        
        modelContext.insert(cacheEntry)
        
        do {
            try modelContext.save()
        } catch {
            print("⚠️ Failed to save file commit cache: \(error)")
        }
    }
    
    // MARK: - File Existence Cache
    
    /// Cache whether a file exists at a given repo state
    public func cacheFileExistence(filePath: String, repoCommitHash: String, exists: Bool, lastFileCommitHash: String? = nil) {
        let cacheEntry = FileCommitCache(
            filePath: filePath,
            repoCommitHash: repoCommitHash,
            lastFileCommitHash: lastFileCommitHash,
            fileExists: exists
        )
        
        modelContext.insert(cacheEntry)
        
        do {
            try modelContext.save()
        } catch {
            print("⚠️ Failed to save file existence cache: \(error)")
        }
    }
    
    /// Check if we have cached information about file existence
    public func getCachedFileExistence(filePath: String, repoCommitHash: String) -> (exists: Bool, lastCommitHash: String?)? {
        let id = FileCommitCache.makeId(filePath: filePath, repoCommitHash: repoCommitHash)
        
        let descriptor = FetchDescriptor<FileCommitCache>(
            predicate: #Predicate { $0.id == id }
        )
        
        do {
            let results = try modelContext.fetch(descriptor)
            if let cacheEntry = results.first {
                cacheEntry.touch()
                try? modelContext.save()
                return (cacheEntry.fileExists, cacheEntry.lastFileCommitHash)
            }
        } catch {
            print("⚠️ Failed to fetch file existence cache: \(error)")
        }
        
        return nil
    }
    
    // MARK: - File Commit Hash
    
    /// Get the current commit hash of a file in the repository
    public func getCurrentFileCommitHash(filePath: String) async throws -> String? {
        let result = try await cliService.execute(
            command: "/usr/bin/git",
            arguments: ["log", "-1", "--format=%H", "--", filePath],
            workingDirectory: repoPath
        )
        
        guard result.isSuccess else {
            // File might not exist
            return nil
        }
        
        let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }
    
    /// Get the current HEAD commit hash of the repository
    public func getCurrentRepoCommitHash() async throws -> String {
        let result = try await cliService.execute(
            command: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD"],
            workingDirectory: repoPath
        )
        
        guard result.isSuccess else {
            throw GitRepoError.gitCommandFailed("Failed to get current commit hash")
        }
        
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Cache Maintenance
    
    /// Invalidate all cache entries for a specific file
    public func invalidateCache(for filePath: String) {
        // Delete blame entries
        let blameDescriptor = FetchDescriptor<GitBlameCache>(
            predicate: #Predicate { $0.filePath == filePath }
        )
        
        // Delete file commit entries
        let fileDescriptor = FetchDescriptor<FileCommitCache>(
            predicate: #Predicate { $0.filePath == filePath }
        )
        
        do {
            let blameEntries = try modelContext.fetch(blameDescriptor)
            let fileEntries = try modelContext.fetch(fileDescriptor)
            
            for entry in blameEntries {
                modelContext.delete(entry)
            }
            
            for entry in fileEntries {
                modelContext.delete(entry)
            }
            
            try modelContext.save()
            print("🗑️ Invalidated cache for file: \(filePath)")
        } catch {
            print("⚠️ Failed to invalidate cache: \(error)")
        }
    }
    
    /// Clean up old cache entries
    public func cleanupOldEntries(olderThan date: Date) {
        let blameDescriptor = FetchDescriptor<GitBlameCache>(
            predicate: #Predicate { $0.lastAccessed < date }
        )
        
        let fileDescriptor = FetchDescriptor<FileCommitCache>(
            predicate: #Predicate { $0.lastAccessed < date }
        )
        
        do {
            let oldBlameEntries = try modelContext.fetch(blameDescriptor)
            let oldFileEntries = try modelContext.fetch(fileDescriptor)
            
            let totalDeleted = oldBlameEntries.count + oldFileEntries.count
            
            for entry in oldBlameEntries {
                modelContext.delete(entry)
            }
            
            for entry in oldFileEntries {
                modelContext.delete(entry)
            }
            
            try modelContext.save()
            
            if totalDeleted > 0 {
                print("🗑️ Cleaned up \(totalDeleted) old cache entries")
            }
        } catch {
            print("⚠️ Failed to cleanup old entries: \(error)")
        }
    }
    
    /// Clean up if we exceed max entries or have old entries
    private func cleanupIfNeeded() {
        // Clean up entries older than maxCacheAge
        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)
        cleanupOldEntries(olderThan: cutoffDate)
        
        // Check if we need to remove excess entries
        Task {
            await removeExcessEntries()
        }
    }
    
    /// Remove oldest entries if we exceed maxEntries
    private func removeExcessEntries() {
        do {
            let blameCount = try modelContext.fetchCount(FetchDescriptor<GitBlameCache>())
            let fileCount = try modelContext.fetchCount(FetchDescriptor<FileCommitCache>())
            let totalCount = blameCount + fileCount
            
            if totalCount > maxEntries {
                let entriesToRemove = totalCount - maxEntries
                
                // Fetch oldest blame entries
                var blameDescriptor = FetchDescriptor<GitBlameCache>()
                blameDescriptor.sortBy = [SortDescriptor(\.lastAccessed, order: .forward)]
                blameDescriptor.fetchLimit = entriesToRemove / 2
                
                // Fetch oldest file entries
                var fileDescriptor = FetchDescriptor<FileCommitCache>()
                fileDescriptor.sortBy = [SortDescriptor(\.lastAccessed, order: .forward)]
                fileDescriptor.fetchLimit = entriesToRemove / 2
                
                let oldBlameEntries = try modelContext.fetch(blameDescriptor)
                let oldFileEntries = try modelContext.fetch(fileDescriptor)
                
                for entry in oldBlameEntries {
                    modelContext.delete(entry)
                }
                
                for entry in oldFileEntries {
                    modelContext.delete(entry)
                }
                
                try modelContext.save()
                print("🗑️ Removed \(oldBlameEntries.count + oldFileEntries.count) excess cache entries")
            }
        } catch {
            print("⚠️ Failed to remove excess entries: \(error)")
        }
    }
    
    /// Get cache statistics
    public func getCacheStatistics() -> (blameEntries: Int, fileEntries: Int, totalSize: Int64) {
        do {
            let blameCount = try modelContext.fetchCount(FetchDescriptor<GitBlameCache>())
            let fileCount = try modelContext.fetchCount(FetchDescriptor<FileCommitCache>())
            
            // Estimate size (this is approximate)
            let estimatedSize = Int64((blameCount * 500) + (fileCount * 200)) // bytes
            
            return (blameCount, fileCount, estimatedSize)
        } catch {
            print("⚠️ Failed to get cache statistics: \(error)")
            return (0, 0, 0)
        }
    }
}
