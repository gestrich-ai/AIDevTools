import ArgumentParser

struct FileTreeSearchCommand: AsyncParsableCommand {
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
        let service = try makeFileTreeService()
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
