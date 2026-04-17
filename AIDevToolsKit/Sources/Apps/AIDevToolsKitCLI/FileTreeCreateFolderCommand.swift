import ArgumentParser
import Foundation

struct FileTreeCreateFolderCommand: AsyncParsableCommand {
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

        let service = try makeFileTreeService()

        do {
            try await service.createFolder(at: parentDirectoryURL, name: folderURL.lastPathComponent)
            print("Created folder: \(folderURL.path)")
        } catch {
            print("Failed to create folder: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
