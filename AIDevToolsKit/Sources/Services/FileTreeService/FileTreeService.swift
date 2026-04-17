import DataPathsService
import Foundation

public actor FileTreeService {
    public struct DirectorySelectionResult: Sendable {
        public let cachedFiles: [FileSystemItem]?
        public let patterns: (patternsByDirectory: [String: [String]], flatPatterns: [String])
        public let rootItems: [FileSystemItem]

        public init(
            rootItems: [FileSystemItem],
            cachedFiles: [FileSystemItem]?,
            patterns: (patternsByDirectory: [String: [String]], flatPatterns: [String])
        ) {
            self.cachedFiles = cachedFiles
            self.patterns = patterns
            self.rootItems = rootItems
        }
    }

    public struct SearchResult: Sendable {
        public let matches: [FileSystemItem]
        public let totalCount: Int

        public init(matches: [FileSystemItem], totalCount: Int) {
            self.matches = matches
            self.totalCount = totalCount
        }
    }

    public enum FileSystemError: Error, LocalizedError {
        case createFailed(String)
        case deleteFailed(String)
        case fileExists(String)
        case invalidPath
        case renameFailed(String)

        public var errorDescription: String? {
            switch self {
            case .createFailed(let reason):
                "Failed to create: \(reason)"
            case .deleteFailed(let reason):
                "Failed to delete: \(reason)"
            case .fileExists(let name):
                "A file or folder named '\(name)' already exists"
            case .invalidPath:
                "Invalid file path"
            case .renameFailed(let reason):
                "Failed to rename: \(reason)"
            }
        }
    }

    private static let lastIndexDurationKey = "lastIndexDuration"

    private let dataPathsService: DataPathsService
    private var cachedAllFiles: [FileSystemItem]?
    private var currentRootItems: [FileSystemItem] = []
    private var currentRootPath: String?
    private var fileSystemMonitor: FileSystemMonitor?
    private var gitignorePatternsByDirectory: [String: [String]] = [:]
    private var ignorePatterns: [String] = []
    private var indexingStartTime: Date?
    private var onProgressChanged: (@Sendable (ProgressState) -> Void)?
    private var onTreeUpdated: (@Sendable ([FileSystemItem]) -> Void)?

    public init(dataPathsService: DataPathsService) {
        self.dataPathsService = dataPathsService
    }

    public func createFile(at url: URL, name: String) throws {
        let fileURL = url.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileSystemError.fileExists(name)
        }

        do {
            try Data().write(to: fileURL)
        } catch {
            throw FileSystemError.createFailed(error.localizedDescription)
        }
    }

    public func createFolder(at url: URL, name: String) throws {
        let folderURL = url.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: folderURL.path) else {
            throw FileSystemError.fileExists(name)
        }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        } catch {
            throw FileSystemError.createFailed(error.localizedDescription)
        }
    }

    public func delete(item: FileSystemItem) throws {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            throw FileSystemError.deleteFailed(error.localizedDescription)
        }
    }

    public func getAllFiles() -> [FileSystemItem] {
        cachedAllFiles ?? []
    }

    public func getCurrentRootPath() -> String? {
        currentRootPath
    }

    public func getIgnorePatterns() -> [String] {
        ignorePatterns
    }

    public func getLastIndexDuration() -> TimeInterval? {
        let duration = UserDefaults.standard.double(forKey: Self.lastIndexDurationKey)
        return duration > 0 ? duration : nil
    }

    public func invalidateCache() {
        guard let rootPath = currentRootPath else { return }
        DirectoryCache.invalidate(for: rootPath, dataPathsService: dataPathsService)
    }

    public func hasCachedFiles() -> Bool {
        if cachedAllFiles != nil {
            return true
        }

        guard let rootPath = currentRootPath else {
            return false
        }

        guard let cache = DirectoryCache.load(for: rootPath, dataPathsService: dataPathsService) else {
            return false
        }

        return cache.isValid()
    }

    public func loadFileContent(from url: URL) -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "Error loading file: \(error.localizedDescription)"
        }
    }

    public func loadRootDirectory() -> [FileSystemItem] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: FileManager.default.homeDirectoryForCurrentUser,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var items: [FileSystemItem] = []
            for itemURL in contents {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
                items.append(FileSystemItem(url: itemURL, isDirectory: resourceValues.isDirectory ?? false))
            }

            items.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return items
        } catch {
            FileTreeLoggers.service.warning("Failed to load root directory: \(error)")
            return []
        }
    }

    public func rename(item: FileSystemItem, to newName: String) throws {
        let parentURL = item.url.deletingLastPathComponent()
        let newURL = parentURL.appendingPathComponent(newName)

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw FileSystemError.fileExists(newName)
        }

        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
        } catch {
            throw FileSystemError.renameFailed(error.localizedDescription)
        }
    }

    public func searchFiles(query: String, limit: Int = 10, caseSensitive: Bool = false) async -> SearchResult {
        let allFiles = getAllFiles()
        guard !query.isEmpty else {
            return SearchResult(matches: [], totalCount: 0)
        }

        let searchQuery = caseSensitive ? query : query.lowercased()
        var exactPrefixMatches: [FileSystemItem] = []
        var exactSubstringMatches: [FileSystemItem] = []
        var pathSubstringMatches: [FileSystemItem] = []
        var totalCount = 0

        for file in allFiles {
            let fileName = caseSensitive ? file.name : file.name.lowercased()
            let filePath = caseSensitive ? file.path : file.path.lowercased()

            if fileName.hasPrefix(searchQuery) {
                totalCount += 1
                exactPrefixMatches.append(file)
            } else if fileName.contains(searchQuery) {
                totalCount += 1
                exactSubstringMatches.append(file)
            } else if filePath.contains(searchQuery) {
                totalCount += 1
                pathSubstringMatches.append(file)
            }
        }

        var matches: [FileSystemItem] = []
        matches.append(contentsOf: exactPrefixMatches.prefix(limit))
        if matches.count < limit {
            matches.append(contentsOf: exactSubstringMatches.prefix(limit - matches.count))
        }
        if matches.count < limit {
            matches.append(contentsOf: pathSubstringMatches.prefix(limit - matches.count))
        }

        return SearchResult(matches: matches, totalCount: totalCount)
    }

    public func selectDirectory(url: URL) async -> DirectorySelectionResult {
        currentRootPath = url.path

        if let cache = DirectoryCache.load(for: url.path, dataPathsService: dataPathsService) {
            let patterns = processCachePatterns(cache)
            gitignorePatternsByDirectory = patterns.patternsByDirectory
            ignorePatterns = patterns.flatPatterns

            var allFiles: [FileSystemItem] = []
            collectAllFilesFromFullTree(items: cache.rootItems, files: &allFiles)
            cachedAllFiles = allFiles

            let result = DirectorySelectionResult(rootItems: cache.rootItems, cachedFiles: nil, patterns: patterns)
            let dataPathsService = dataPathsService
            Task.detached { [weak self] in
                await self?.revalidateCacheInBackground(url: url, dataPathsService: dataPathsService)
            }
            return result
        }

        return await performFreshScan(url: url)
    }

    public func startMonitoring(
        onTreeUpdated: @escaping @Sendable ([FileSystemItem]) -> Void,
        onProgressChanged: @escaping @Sendable (ProgressState) -> Void
    ) {
        guard let rootPath = currentRootPath else {
            return
        }

        self.onProgressChanged = onProgressChanged
        self.onTreeUpdated = onTreeUpdated
        fileSystemMonitor = FileSystemMonitor { [weak self] changedPaths in
            await self?.handleFileSystemChanges(changedPaths)
        }

        Task {
            await fileSystemMonitor?.startMonitoring(path: rootPath)
        }
    }

    public func stopMonitoring() async {
        await fileSystemMonitor?.stopMonitoring()
        fileSystemMonitor = nil
        onProgressChanged = nil
        onTreeUpdated = nil
    }

    private static func collectAllFilesFromFullTreeNonIsolated(items: [FileSystemItem], files: inout [FileSystemItem]) {
        for item in items {
            if item.isDirectory {
                if let children = item.children {
                    collectAllFilesFromFullTreeNonIsolated(items: children, files: &files)
                }
            } else {
                files.append(item)
            }
        }
    }

    private static func collectGitignoreFilesIntoNonIsolated(from url: URL, patternsByDirectory: inout [String: [String]]) {
        let gitignoreURL = url.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: gitignoreURL.path) {
            do {
                let content = try String(contentsOf: gitignoreURL, encoding: .utf8)
                let patterns = content
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                if !patterns.isEmpty {
                    patternsByDirectory[url.path] = patterns
                }
            } catch {
                FileTreeLoggers.service.warning("Failed to read .gitignore at \(gitignoreURL.path): \(error)")
            }
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for itemURL in contents {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    collectGitignoreFilesIntoNonIsolated(from: itemURL, patternsByDirectory: &patternsByDirectory)
                }
            }
        } catch {
            FileTreeLoggers.service.warning("Failed to scan directory \(url.path): \(error)")
        }
    }

    private static func loadDirectoryTreeRecursivelyNonIsolated(url: URL, ignorePatterns: [String]) async -> [FileSystemItem] {
        let item = FileSystemItem(url: url, isDirectory: true)
        let children = item.loadChildren(ignorePatterns: ignorePatterns)

        for child in children where child.isDirectory {
            let childChildren = await loadDirectoryTreeRecursivelyNonIsolated(url: child.url, ignorePatterns: ignorePatterns)
            child.setChildren(childChildren)
        }

        return children
    }

    private static func scanGitignoreFilesNonIsolated(from url: URL) -> (patternsByDirectory: [String: [String]], flatPatterns: [String]) {
        var patternsByDirectory: [String: [String]] = [:]
        collectGitignoreFilesIntoNonIsolated(from: url, patternsByDirectory: &patternsByDirectory)
        return (patternsByDirectory, Array(patternsByDirectory.values.flatMap(\.self)))
    }

    private func collectAllFilesFromFullTree(items: [FileSystemItem], files: inout [FileSystemItem]) {
        for item in items {
            if item.isDirectory {
                if let children = item.children {
                    collectAllFilesFromFullTree(items: children, files: &files)
                }
            } else {
                files.append(item)
            }
        }
    }

    private func collectGitignoreFilesInto(from url: URL, patternsByDirectory: inout [String: [String]]) {
        let gitignoreURL = url.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: gitignoreURL.path) {
            do {
                let content = try String(contentsOf: gitignoreURL, encoding: .utf8)
                let patterns = content
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                if !patterns.isEmpty {
                    patternsByDirectory[url.path] = patterns
                }
            } catch {
                FileTreeLoggers.service.warning("Failed to read .gitignore at \(gitignoreURL.path): \(error)")
            }
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for itemURL in contents {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    collectGitignoreFilesInto(from: itemURL, patternsByDirectory: &patternsByDirectory)
                }
            }
        } catch {
            FileTreeLoggers.service.warning("Failed to scan directory \(url.path): \(error)")
        }
    }

    private func findItem(at path: String, in items: [FileSystemItem]) -> FileSystemItem? {
        for item in items {
            if item.path == path {
                return item
            }

            if path.hasPrefix(item.path + "/"),
                let children = item.children,
                !children.isEmpty,
                let found = findItem(at: path, in: children)
            {
                return found
            }
        }

        return nil
    }

    private func handleFileSystemChanges(_ changedPaths: [String]) {
        guard let rootPath = currentRootPath else {
            return
        }

        var updated = false
        var shouldReloadRoot = false

        for changedPath in changedPaths {
            if changedPath == rootPath {
                shouldReloadRoot = true
                continue
            }

            if let item = findItem(at: changedPath, in: currentRootItems) {
                let freshChildren = item.loadChildren(ignorePatterns: ignorePatterns)
                updateCachedFilesForDirectory(directoryPath: changedPath, newChildren: freshChildren)
                item.setChildren(freshChildren)
                updated = true
            } else {
                let pathComponents = changedPath
                    .replacingOccurrences(of: rootPath + "/", with: "")
                    .components(separatedBy: "/")
                if pathComponents.count == 1 {
                    shouldReloadRoot = true
                }
            }
        }

        if shouldReloadRoot {
            let rootItem = FileSystemItem(url: URL(fileURLWithPath: rootPath), isDirectory: true)
            let freshRootItems = rootItem.loadChildren(ignorePatterns: ignorePatterns)
            updateCachedFilesForRootLevel(newRootItems: freshRootItems)
            currentRootItems = freshRootItems
            updated = true
        }

        if updated {
            onTreeUpdated?(currentRootItems)
        }
    }

    private func loadDirectoryTreeRecursively(url: URL, ignorePatterns: [String]) async -> [FileSystemItem] {
        let item = FileSystemItem(url: url, isDirectory: true)
        let children = item.loadChildren(ignorePatterns: ignorePatterns)

        for child in children where child.isDirectory {
            let childChildren = await loadDirectoryTreeRecursively(url: child.url, ignorePatterns: ignorePatterns)
            child.setChildren(childChildren)
        }

        return children
    }

    private func performFreshScan(url: URL) async -> DirectorySelectionResult {
        indexingStartTime = Date()
        let gitignoreData = scanGitignoreFiles(from: url)
        let rootItems = await loadDirectoryTreeRecursively(url: url, ignorePatterns: gitignoreData.flatPatterns)
        var allFiles: [FileSystemItem] = []
        collectAllFilesFromFullTree(items: rootItems, files: &allFiles)

        gitignorePatternsByDirectory = gitignoreData.patternsByDirectory
        ignorePatterns = gitignoreData.flatPatterns
        cachedAllFiles = allFiles
        saveTreeToCache(rootItems: rootItems)

        return DirectorySelectionResult(rootItems: rootItems, cachedFiles: nil, patterns: gitignoreData)
    }

    private func processCachePatterns(_ cache: DirectoryCache) -> (patternsByDirectory: [String: [String]], flatPatterns: [String]) {
        var patternsByDirectory: [String: [String]] = [:]
        for pattern in cache.ignorePatterns {
            patternsByDirectory[pattern.directoryPath] = pattern.patterns
        }
        return (patternsByDirectory, Array(patternsByDirectory.values.flatMap(\.self)))
    }

    private func revalidateCacheInBackground(url: URL, dataPathsService: DataPathsService) async {
        updateProgressState(.revalidating)
        let startTime = Date()
        let gitignoreData = Self.scanGitignoreFilesNonIsolated(from: url)
        let freshRootItems = await Self.loadDirectoryTreeRecursivelyNonIsolated(url: url, ignorePatterns: gitignoreData.flatPatterns)
        var allFiles: [FileSystemItem] = []
        Self.collectAllFilesFromFullTreeNonIsolated(items: freshRootItems, files: &allFiles)

        updateCacheAfterRevalidation(
            url: url,
            freshRootItems: freshRootItems,
            allFiles: allFiles,
            gitignoreData: gitignoreData,
            dataPathsService: dataPathsService,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private func saveTreeToCache(rootItems: [FileSystemItem]) {
        guard let rootPath = currentRootPath else {
            return
        }

        currentRootItems = rootItems
        let ignorePatterns = gitignorePatternsByDirectory.map(DirectoryCache.GitIgnorePattern.init)
        let cache = DirectoryCache(
            rootPath: rootPath,
            lastModified: Date(),
            ignorePatterns: ignorePatterns,
            rootItems: rootItems
        )
        cache.save(dataPathsService: dataPathsService)

        if let indexingStartTime {
            UserDefaults.standard.set(Date().timeIntervalSince(indexingStartTime), forKey: Self.lastIndexDurationKey)
        }
        self.indexingStartTime = nil
    }

    private func scanGitignoreFiles(from url: URL) -> (patternsByDirectory: [String: [String]], flatPatterns: [String]) {
        var patternsByDirectory: [String: [String]] = [:]
        collectGitignoreFilesInto(from: url, patternsByDirectory: &patternsByDirectory)
        return (patternsByDirectory, Array(patternsByDirectory.values.flatMap(\.self)))
    }

    private func updateCachedFilesForDirectory(directoryPath: String, newChildren: [FileSystemItem]) {
        guard var allFiles = cachedAllFiles else {
            return
        }

        allFiles.removeAll { $0.path.hasPrefix(directoryPath + "/") }
        allFiles.append(contentsOf: newChildren.filter { !$0.isDirectory })
        cachedAllFiles = allFiles
    }

    private func updateCachedFilesForRootLevel(newRootItems: [FileSystemItem]) {
        guard let rootPath = currentRootPath, var allFiles = cachedAllFiles else {
            return
        }

        allFiles.removeAll { file in
            (file.path as NSString).deletingLastPathComponent == rootPath
        }
        allFiles.append(contentsOf: newRootItems.filter { !$0.isDirectory })
        cachedAllFiles = allFiles
    }

    private func updateCacheAfterRevalidation(
        url: URL,
        freshRootItems: [FileSystemItem],
        allFiles: [FileSystemItem],
        gitignoreData: (patternsByDirectory: [String: [String]], flatPatterns: [String]),
        dataPathsService: DataPathsService,
        duration: TimeInterval
    ) {
        gitignorePatternsByDirectory = gitignoreData.patternsByDirectory
        ignorePatterns = gitignoreData.flatPatterns
        currentRootItems = freshRootItems
        cachedAllFiles = allFiles

        let cache = DirectoryCache(
            rootPath: url.path,
            lastModified: Date(),
            ignorePatterns: gitignorePatternsByDirectory.map(DirectoryCache.GitIgnorePattern.init),
            rootItems: freshRootItems
        )
        cache.save(dataPathsService: dataPathsService)
        UserDefaults.standard.set(duration, forKey: Self.lastIndexDurationKey)
        onProgressChanged?(.idle)
    }

    private func updateProgressState(_ state: ProgressState) {
        onProgressChanged?(state)
    }
}
