import ArgumentParser
import FileTreeService
import Foundation

struct FileTreeDeleteCommand: AsyncParsableCommand {
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

        let service = try makeFileTreeService()
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
