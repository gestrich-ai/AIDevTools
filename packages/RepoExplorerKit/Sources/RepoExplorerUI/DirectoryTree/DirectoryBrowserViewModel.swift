import Foundation
import Observation
import RepoExplorerFileTreeService

@MainActor
@Observable
public final class DirectoryBrowserViewModel {
    public private(set) var currentRootPath: String?
    public private(set) var fileContent: String = ""
    public private(set) var progressState: ProgressState = .idle
    public private(set) var rootItems: [FileSystemItem] = []
    public private(set) var selectedItem: FileSystemItem?

    private let fileTreeService: FileTreeService
    private let expandedPathsKey = "RepoExplorerUI.expandedPaths"
    private let selectedPathKey = "RepoExplorerUI.selectedPath"
    private var ignorePatterns: [String] = []

    public var isIndexing: Bool {
        progressState.isActive
    }

    public var indexingProgress: String {
        progressState.message
    }

    public init(fileTreeService: FileTreeService) {
        self.fileTreeService = fileTreeService
    }

    deinit {
        let fileTreeService = self.fileTreeService
        Task {
            await fileTreeService.stopMonitoring()
        }
    }

    public func loadRootDirectory() async {
        rootItems = await fileTreeService.loadRootDirectory()
    }

    public func selectDirectory(url: URL) async {
        progressState = .loadingCache
        currentRootPath = url.path
        await fileTreeService.stopMonitoring()

        let result = await fileTreeService.selectDirectory(url: url)
        ignorePatterns = result.patterns.flatPatterns
        rootItems = result.rootItems
        progressState = .idle
        restoreExpandedState()

        await fileTreeService.startMonitoring(
            onTreeUpdated: { [weak self] updatedTree in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.rootItems = updatedTree
                    self.restoreExpandedState()
                }
            },
            onProgressChanged: { [weak self] updatedProgressState in
                Task { @MainActor [weak self] in
                    self?.progressState = updatedProgressState
                }
            }
        )
    }

    public func stopMonitoring() async {
        await fileTreeService.stopMonitoring()
    }

    public func toggleExpansion(for item: FileSystemItem) {
        item.isExpanded.toggle()

        if item.isExpanded && item.children?.isEmpty == true {
            loadChildren(item)
        }

        saveExpandedState()
    }

    public func loadChildrenIfNeeded(for item: FileSystemItem) {
        guard item.children?.isEmpty == true else {
            return
        }

        loadChildren(item)
    }

    public func selectItem(_ item: FileSystemItem) {
        selectedItem = item
        UserDefaults.standard.set(item.path, forKey: selectedPathKey)

        guard !item.isDirectory else {
            fileContent = ""
            return
        }

        Task {
            let content = await fileTreeService.loadFileContent(from: item.url)
            await MainActor.run { [weak self] in
                self?.fileContent = content
            }
        }
    }

    public func getAllFiles() async -> [FileSystemItem] {
        await fileTreeService.getAllFiles()
    }

    public func searchFiles(
        query: String,
        limit: Int = 10,
        caseSensitive: Bool = false
    ) async -> FileTreeService.SearchResult {
        await fileTreeService.searchFiles(query: query, limit: limit, caseSensitive: caseSensitive)
    }

    public func hasCachedFiles() async -> Bool {
        await fileTreeService.hasCachedFiles()
    }

    public func getLastIndexDuration() async -> TimeInterval? {
        await fileTreeService.getLastIndexDuration()
    }

    public func createFile(in parent: FileSystemItem?, name: String) async throws {
        let targetURL = try targetURL(for: parent)
        try await fileTreeService.createFile(at: targetURL, name: name)
        await reloadContents(of: parent)
    }

    public func createFolder(in parent: FileSystemItem?, name: String) async throws {
        let targetURL = try targetURL(for: parent)
        try await fileTreeService.createFolder(at: targetURL, name: name)
        await reloadContents(of: parent)
    }

    public func deleteItem(_ item: FileSystemItem) async throws {
        try await fileTreeService.delete(item: item)
        if selectedItem?.id == item.id {
            selectedItem = nil
            fileContent = ""
        }

        let parentPath = (item.path as NSString).deletingLastPathComponent
        let parentItem = findItem(withPath: parentPath, in: rootItems)
        await reloadContents(of: parentItem)
    }

    public func renameItem(_ item: FileSystemItem, to newName: String) async throws {
        try await fileTreeService.rename(item: item, to: newName)
        let parentPath = (item.path as NSString).deletingLastPathComponent
        let parentItem = findItem(withPath: parentPath, in: rootItems)
        await reloadContents(of: parentItem)
    }

    private func loadChildren(_ item: FileSystemItem) {
        let currentPatterns = ignorePatterns
        Task.detached {
            let children = item.loadChildren(ignorePatterns: currentPatterns)
            await MainActor.run {
                item.setChildren(children)
            }
        }
    }

    private func targetURL(for parent: FileSystemItem?) throws -> URL {
        if let parent, parent.isDirectory {
            return parent.url
        }

        if let currentRootPath {
            return URL(fileURLWithPath: currentRootPath)
        }

        throw FileTreeService.FileSystemError.invalidPath
    }

    private func reloadContents(of parent: FileSystemItem?) async {
        if let parent {
            let children = parent.loadChildren(ignorePatterns: ignorePatterns)
            parent.setChildren(children)
            saveExpandedState()
            return
        }

        guard let currentRootPath else {
            return
        }

        rootItems = await fileTreeService.selectDirectory(url: URL(fileURLWithPath: currentRootPath)).rootItems
        restoreExpandedState()
    }

    private func saveExpandedState() {
        var expandedPaths: [String] = []
        collectExpandedPaths(items: rootItems, paths: &expandedPaths)
        UserDefaults.standard.set(expandedPaths, forKey: expandedPathsKey)
    }

    private func collectExpandedPaths(items: [FileSystemItem], paths: inout [String]) {
        for item in items where item.isExpanded {
            paths.append(item.path)
            if let children = item.children {
                collectExpandedPaths(items: children, paths: &paths)
            }
        }
    }

    private func restoreExpandedState() {
        guard let expandedPaths = UserDefaults.standard.array(forKey: expandedPathsKey) as? [String] else {
            restoreSelectedItemIfNeeded()
            return
        }

        restoreExpansion(items: rootItems, expandedPaths: Set(expandedPaths))
        restoreSelectedItemIfNeeded()
    }

    private func restoreExpansion(items: [FileSystemItem], expandedPaths: Set<String>) {
        for item in items where expandedPaths.contains(item.path) {
            item.isExpanded = true
            let children = item.loadChildren(ignorePatterns: ignorePatterns)
            item.setChildren(children)
            if !children.isEmpty {
                restoreExpansion(items: children, expandedPaths: expandedPaths)
            }
        }
    }

    private func restoreSelectedItemIfNeeded() {
        guard let selectedPath = UserDefaults.standard.string(forKey: selectedPathKey),
              let item = findItem(withPath: selectedPath, in: rootItems)
        else {
            return
        }

        selectedItem = item
        guard !item.isDirectory else {
            return
        }

        Task {
            let content = await fileTreeService.loadFileContent(from: item.url)
            await MainActor.run { [weak self] in
                self?.fileContent = content
            }
        }
    }

    private func findItem(withPath path: String, in items: [FileSystemItem]) -> FileSystemItem? {
        for item in items {
            if item.path == path {
                return item
            }

            if let children = item.children,
               let found = findItem(withPath: path, in: children) {
                return found
            }
        }

        return nil
    }
}
