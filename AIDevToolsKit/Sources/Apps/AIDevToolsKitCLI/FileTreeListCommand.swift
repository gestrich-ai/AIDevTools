import ArgumentParser

struct FileTreeListCommand: AsyncParsableCommand {
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
        let service = try makeFileTreeService()
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
