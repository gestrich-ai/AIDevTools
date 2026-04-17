import DataPathsService
import Foundation

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
            FileTreeLoggers.cache.debug("Cache invalid: root path does not exist", metadata: ["rootPath": .string(rootPath)])
            return false
        }

        let maxAge: TimeInterval = 300
        let age = Date().timeIntervalSince(lastModified)
        if age > maxAge {
            FileTreeLoggers.cache.debug(
                "Cache invalid: too old",
                metadata: ["ageSeconds": .stringConvertible(Int(age)), "maxAgeSeconds": .stringConvertible(Int(maxAge))]
            )
            return false
        }

        FileTreeLoggers.cache.debug("Cache valid", metadata: ["ageSeconds": .stringConvertible(Int(age))])
        return true
    }

    public func save(dataPathsService: DataPathsService) {
        do {
            let fileURL = try Self.cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
            let data = try JSONEncoder().encode(self)
            try data.write(to: fileURL)
            FileTreeLoggers.cache.debug("Saved cache", metadata: ["path": .string(fileURL.path)])
        } catch {
            FileTreeLoggers.cache.warning("Failed to save cache: \(error)")
        }
    }

    public static func getCacheFileURL(for rootPath: String, dataPathsService: DataPathsService) throws -> URL {
        try cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
    }

    public static func invalidate(for rootPath: String, dataPathsService: DataPathsService) {
        do {
            let fileURL = try cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
            try? FileManager.default.removeItem(at: fileURL)
            FileTreeLoggers.cache.debug("Invalidated cache", metadata: ["rootPath": .string(rootPath)])
        } catch {
            FileTreeLoggers.cache.warning("Failed to invalidate cache: \(error)")
        }
    }

    public static func load(for rootPath: String, dataPathsService: DataPathsService) -> DirectoryCache? {
        do {
            let fileURL = try cacheFileURL(for: rootPath, dataPathsService: dataPathsService)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                FileTreeLoggers.cache.debug("No cache file found", metadata: ["path": .string(fileURL.path)])
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            let cache = try JSONDecoder().decode(DirectoryCache.self, from: data)

            guard cache.rootPath == rootPath else {
                FileTreeLoggers.cache.warning(
                    "Cache root path mismatch",
                    metadata: ["expectedRootPath": .string(rootPath), "cachedRootPath": .string(cache.rootPath)]
                )
                return nil
            }

            FileTreeLoggers.cache.debug(
                "Loaded cache",
                metadata: [
                    "rootItems": .stringConvertible(cache.rootItems.count),
                    "ignorePatternGroups": .stringConvertible(cache.ignorePatterns.count),
                ]
            )
            return cache
        } catch {
            FileTreeLoggers.cache.warning("Failed to load cache: \(error)")
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
        let cacheDirectory = try dataPathsService.path(for: .fileTreeCache)
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
