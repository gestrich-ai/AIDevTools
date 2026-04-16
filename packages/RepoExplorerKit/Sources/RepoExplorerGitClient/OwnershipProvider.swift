import Foundation

/// Simple provider for getting enriched ownership analysis information
public final class OwnershipProvider: @unchecked Sendable {
    private let gitRepo: GitRepo
    
    public init(repoPath: String) {
        self.gitRepo = GitRepo(repoPath: repoPath)
    }
    
    /// Get ownership analysis for a file/line using git blame or last commit
    public func getOwnershipAnalysis(
        for filePath: String,
        line: Int? = nil
    ) async throws -> OwnershipAnalysis? {
        let ownership: Ownership?
        let method: AttributionMethod
        
        if let lineNumber = line {
            // Try git blame for specific line
            ownership = try await gitRepo.getOwnership(for: filePath, line: lineNumber)
            method = .gitBlame
        } else {
            // Fall back to last commit
            ownership = try await gitRepo.getLastCommitToFile(for: filePath)
            method = .lastCommit
        }
        
        guard let ownership else { return nil }
        
        return OwnershipAnalysis(from: ownership, attributionMethod: method)
    }
    
    /// Batch process multiple files/lines with optional progress reporting
    public func batchGetOwnership(
        for items: [(path: String, line: Int?)],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [OwnershipAnalysis] {
        var results: [OwnershipAnalysis] = []
        
        for (index, item) in items.enumerated() {
            progress?(index, items.count)
            
            if let analysis = try await getOwnershipAnalysis(for: item.path, line: item.line) {
                results.append(analysis)
            }
        }
        
        progress?(items.count, items.count)
        return results
    }
    
    /// Checkout a specific commit before performing git operations
    public func checkoutCommit(_ commitHash: String) async throws {
        try await gitRepo.checkoutCommit(commitHash)
    }
}
