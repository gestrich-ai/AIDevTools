import ArgumentParser
import Foundation
import RepoExplorerDataPathsService
import RepoExplorerFileTreeService

struct RepoExplorerIndexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Index a directory and write the disk cache"
    )

    @Argument(help: "Directory path to index")
    var path: String

    @Flag(name: .long, help: "Show ignore pattern details")
    var verbose: Bool = false

    func run() async throws {
        let directoryURL = try validatedDirectoryURL(for: path)
        let service = try makeService()

        print("Indexing \(directoryURL.path)...")
        let startTime = Date()
        let result = await service.selectDirectory(url: directoryURL)
        let allFiles = await service.getAllFiles()
        let duration = Date().timeIntervalSince(startTime)

        print("Index complete.")
        print("Root items: \(result.rootItems.count)")
        print("Indexed files: \(allFiles.count)")
        print("Duration: \(String(format: "%.2f", duration))s")
        print("Ignore patterns: \(result.patterns.flatPatterns.count)")

        if verbose {
            for pattern in result.patterns.flatPatterns.sorted() {
                print(pattern)
            }
        }
    }
}

struct RepoExplorerListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List cached files for a directory"
    )

    @Argument(help: "Directory path to read from cache")
    var path: String

    @Option(name: .long, help: "Optional glob filter such as '*.swift'")
    var filter: String?

    @Flag(name: .long, help: "Show absolute paths")
    var fullPaths: Bool = false

    @Option(name: .long, help: "Limit the number of results")
    var limit: Int?

    func run() async throws {
        let directoryURL = try validatedDirectoryURL(for: path)
        let service = try makeService()
        _ = await service.selectDirectory(url: directoryURL)

        let files = try filteredFiles(
            from: await service.getAllFiles(),
            rootPath: directoryURL.path,
            filter: filter
        )

        guard !files.isEmpty else {
            print("No cached files found.")
            return
        }

        let filesToPrint = limit.map { Array(files.prefix($0)) } ?? files
        for file in filesToPrint {
            print(displayPath(for: file, rootPath: directoryURL.path, fullPaths: fullPaths))
        }

        if let limit, files.count > limit {
            print("... and \(files.count - limit) more")
        }
    }
}

struct RepoExplorerSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Fuzzy search cached files"
    )

    @Argument(help: "Directory path to search")
    var path: String

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Limit the number of results")
    var limit: Int = 20

    @Flag(name: .long, help: "Match case exactly")
    var caseSensitive: Bool = false

    @Flag(name: .long, help: "Show absolute paths")
    var fullPaths: Bool = false

    func run() async throws {
        let directoryURL = try validatedDirectoryURL(for: path)
        let service = try makeService()
        _ = await service.selectDirectory(url: directoryURL)

        let result = await service.searchFiles(query: query, limit: limit, caseSensitive: caseSensitive)
        guard result.totalCount > 0 else {
            print("No matches found for '\(query)'.")
            return
        }

        for file in result.matches {
            print(displayPath(for: file, rootPath: directoryURL.path, fullPaths: fullPaths))
        }

        if result.totalCount > result.matches.count {
            print("... and \(result.totalCount - result.matches.count) more")
        }
    }
}

struct RepoExplorerStatsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Print file counts, type breakdown, and ignore summary"
    )

    @Argument(help: "Directory path to summarize")
    var path: String

    func run() async throws {
        let directoryURL = try validatedDirectoryURL(for: path)
        let service = try makeService()
        let selection = await service.selectDirectory(url: directoryURL)
        let files = await service.getAllFiles()

        guard !files.isEmpty else {
            print("No cached files found.")
            return
        }

        print("Directory: \(directoryURL.path)")
        print("Files: \(files.count)")

        if let duration = await service.getLastIndexDuration() {
            print("Last index duration: \(String(format: "%.2f", duration))s")
        }

        let patterns = selection.patterns.flatPatterns.sorted()
        print("Ignore patterns: \(patterns.count)")
        if !patterns.isEmpty {
            let preview = patterns.prefix(10).joined(separator: ", ")
            print("Ignore preview: \(preview)")
        }

        let counts = Dictionary(grouping: files) { file -> String in
            let ext = file.url.pathExtension
            return ext.isEmpty ? "(no extension)" : ".\(ext)"
        }
        .mapValues(\.count)
        .sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }

        for (fileType, count) in counts {
            print("\(fileType): \(count)")
        }
    }
}

struct RepoExplorerCreateFileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-file",
        abstract: "Create an empty file at a path"
    )

    @Argument(help: "File path to create")
    var path: String

    func run() async throws {
        let fileURL = absoluteURL(for: path)
        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentDirectoryURL.path) else {
            throw ValidationError("Parent directory does not exist: \(parentDirectoryURL.path)")
        }

        let service = try makeService()

        do {
            try await service.createFile(at: parentDirectoryURL, name: fileURL.lastPathComponent)
            print("Created file: \(fileURL.path)")
        } catch {
            print("Failed to create file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

struct RepoExplorerCreateFolderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-folder",
        abstract: "Create a folder at a path"
    )

    @Argument(help: "Folder path to create")
    var path: String

    func run() async throws {
        let folderURL = absoluteURL(for: path)
        let parentDirectoryURL = folderURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentDirectoryURL.path) else {
            throw ValidationError("Parent directory does not exist: \(parentDirectoryURL.path)")
        }

        let service = try makeService()

        do {
            try await service.createFolder(at: parentDirectoryURL, name: folderURL.lastPathComponent)
            print("Created folder: \(folderURL.path)")
        } catch {
            print("Failed to create folder: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

struct RepoExplorerDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a file or folder"
    )

    @Argument(help: "Path to the file or folder to delete")
    var path: String

    @Flag(name: .long, help: "Skip the confirmation prompt")
    var force: Bool = false

    func run() async throws {
        let itemURL = absoluteURL(for: path)
        guard FileManager.default.fileExists(atPath: itemURL.path) else {
            throw ValidationError("Path does not exist: \(itemURL.path)")
        }

        let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = resourceValues.isDirectory ?? false
        let itemType = isDirectory ? "folder" : "file"

        if !force {
            print("Delete \(itemType) '\(itemURL.lastPathComponent)' at \(itemURL.path)? [y/N]", terminator: " ")
            fflush(stdout)
            let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        let service = try makeService()
        let item = FileSystemItem(url: itemURL, isDirectory: isDirectory)

        do {
            try await service.delete(item: item)
            print("Deleted: \(itemURL.path)")
        } catch {
            print("Failed to delete item: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

struct RepoExplorerRenameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename or move a file or folder"
    )

    @Argument(help: "Existing path")
    var oldPath: String

    @Argument(help: "New path or new name")
    var newPath: String

    func run() async throws {
        let sourceURL = absoluteURL(for: oldPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ValidationError("Path does not exist: \(sourceURL.path)")
        }

        let resourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = resourceValues.isDirectory ?? false
        let destinationURL = destinationURL(from: sourceURL, input: newPath)

        guard sourceURL.deletingLastPathComponent() == destinationURL.deletingLastPathComponent() else {
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                print("Renamed: \(sourceURL.path) -> \(destinationURL.path)")
                return
            } catch {
                throw ValidationError("Failed to move item: \(error.localizedDescription)")
            }
        }

        let service = try makeService()
        let item = FileSystemItem(url: sourceURL, isDirectory: isDirectory)

        do {
            try await service.rename(item: item, to: destinationURL.lastPathComponent)
            print("Renamed: \(sourceURL.path) -> \(destinationURL.path)")
        } catch {
            print("Failed to rename item: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

private func absoluteURL(for path: String) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(path)
        .standardizedFileURL
}

private func destinationURL(from sourceURL: URL, input: String) -> URL {
    let inputURL = URL(filePath: input)
    if inputURL.pathComponents.count > 1 || input.hasPrefix("/") || input.hasPrefix(".") {
        return absoluteURL(for: input)
    }
    return sourceURL.deletingLastPathComponent().appendingPathComponent(input)
}

private func displayPath(for file: FileSystemItem, rootPath: String, fullPaths: Bool) -> String {
    guard !fullPaths else {
        return file.path
    }

    let rootURL = URL(filePath: rootPath)
    let relativePath = file.url.path(percentEncoded: false).replacingOccurrences(of: rootURL.path(percentEncoded: false) + "/", with: "")
    return relativePath
}

private func filteredFiles(from files: [FileSystemItem], rootPath: String, filter: String?) throws -> [FileSystemItem] {
    let sortedFiles = files.sorted { lhs, rhs in
        lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }

    guard let filter, !filter.isEmpty else {
        return sortedFiles
    }

    guard let predicate = NSPredicate(format: "SELF LIKE %@", filter) as NSPredicate? else {
        return sortedFiles
    }

    return sortedFiles.filter { file in
        let relativePath = displayPath(for: file, rootPath: rootPath, fullPaths: false)
        return predicate.evaluate(with: relativePath) || predicate.evaluate(with: file.name)
    }
}

private func makeService() throws -> FileTreeService {
    let dataPathsService = try DataPathsService()
    return FileTreeService(dataPathsService: dataPathsService)
}

private func validatedDirectoryURL(for path: String) throws -> URL {
    let directoryURL = absoluteURL(for: path)
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

    guard exists else {
        throw ValidationError("Path does not exist: \(directoryURL.path)")
    }

    guard isDirectory.boolValue else {
        throw ValidationError("Path is not a directory: \(directoryURL.path)")
    }

    return directoryURL
}
