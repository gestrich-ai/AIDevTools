import ArgumentParser
import FileTreeService
import Foundation

struct FileTreeStatsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Print file counts, type breakdown, and ignore summary"
    )

    @Argument(help: "Directory path to summarize")
    var path: String

    func run() async throws {
        let directoryURL = try validatedDirectoryURL(for: path)
        let service = try makeFileTreeService()
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
