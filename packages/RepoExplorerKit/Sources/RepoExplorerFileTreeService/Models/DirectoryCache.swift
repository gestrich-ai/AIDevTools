import Foundation
import RepoExplorerDataPathsService

public struct DirectoryCache: Codable {
    public struct GitIgnorePattern: Codable {
        public let directoryPath: String
        public let patterns: [String]

        public init(directoryPath: String, patterns: [String]) {
            self.directoryPath = directoryPath
            self.patterns = patterns
        }
    }

    public let ignorePatterns: [GitIgnorePattern]
    public let lastModified: Date
    public let rootItems: [FileSystemItem]
    public let rootPath: String

    public init(rootPath: String, lastModified: Date, ignorePatterns: [GitIgnorePattern], rootItems: [FileSystemItem]) {
        self.ignorePatterns = ignorePatterns
        self.lastModified = lastModified
        self.rootItems = rootItems
        self.rootPath = rootPath
    }

    public func countFiles() -> Int {
        var count = 0
        countFilesRecursive(items: rootItems, count: &count)
        return count
    }

    public func isValid() -> Bool {
        guard FileManager.default.fileExists(atPath: rootPath) else {
            print("Cache invalid: root path doesn't exist")
            return false
        }

        let maxAge: TimeInterval = 300
        let age = Date().timeIntervalSince(lastModified)
        if age > maxAge {
            print("Cache invalid: too old (\(Int(age))s > \(Int(maxAge))s)")
            return false
        }

        print("Cache valid: age \(Int(age))s")
        return true
    }

    public func save(dataPathsService: DataPathsService) {
        do {
            let fileURL = try Self.cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
            let data = try JSONEncoder().encode(self)
            try data.write(to: fileURL)
            print("Saved cache to: \(fileURL.path)")
        } catch {
            print("Failed to save cache: \(error)")
        }
    }

    public static func getCacheFileURL(for rootPath: String, dataPathsService: DataPathsService) throws -> URL {
        try cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
    }

    public static func invalidate(for rootPath: String, dataPathsService: DataPathsService) {
        do {
            let fileURL = try cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
            try? FileManager.default.removeItem(at: fileURL)
            print("Invalidated cache for: \(rootPath)")
        } catch {
            print("Failed to invalidate cache: \(error)")
        }
    }

    public static func load(for rootPath: String, dataPathsService: DataPathsService) -> DirectoryCache? {
        do {
            let fileURL = try cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("No cache file found at: \(fileURL.path)")
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            let cache = try JSONDecoder().decode(DirectoryCache.self, from: data)

            guard cache.rootPath == rootPath else {
                print("Cache root path mismatch")
                return nil
            }

            print("Loaded cache with \(cache.rootItems.count) root items and \(cache.ignorePatterns.count) gitignore patterns")
            return cache
        } catch {
            print("Failed to load cache: \(error)")
            return nil
        }
    }

    private func countFilesRecursive(items: [FileSystemItem], count: inout Int) {
        for item in items {
            if item.isDirectory {
                if let children = item.children {
                    countFilesRecursive(items: children, count: &count)
                }
            } else {
                count += 1
            }
        }
    }

    private static func cacheFileURL(for rootPath: String, dataPathsService: DataPathsService) throws -> URL {
        let cacheDirectory = try dataPathsService.path(for: "file-tree", subdirectory: "cache")
        return cacheDirectory.appendingPathComponent("cache_\(stableHash(for: rootPath)).json")
    }

    private static func stableHash(for string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let fnvPrime: UInt64 = 1_099_511_628_211

        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }

        return String(hash)
    }
}
