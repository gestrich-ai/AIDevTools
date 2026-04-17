import ArgumentParser
import Foundation

struct FileTreeIndexCommand: AsyncParsableCommand {
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
        let service = try makeFileTreeService()

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
