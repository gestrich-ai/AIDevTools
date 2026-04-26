import ArgumentParser
import FileTreeService
import Foundation

struct FileTreeRenameCommand: AsyncParsableCommand {
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
        let destinationURL = resolvedDestinationURL(from: sourceURL, input: newPath)

        guard sourceURL.deletingLastPathComponent() == destinationURL.deletingLastPathComponent() else {
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                print("Renamed: \(sourceURL.path) -> \(destinationURL.path)")
                return
            } catch {
                throw ValidationError("Failed to move item: \(error.localizedDescription)")
            }
        }

        let service = try makeFileTreeService()
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
