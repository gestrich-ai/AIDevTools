import ArgumentParser
import Foundation

struct FileTreeCreateFileCommand: AsyncParsableCommand {
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

        let service = try makeFileTreeService()

        do {
            try await service.createFile(at: parentDirectoryURL, name: fileURL.lastPathComponent)
            print("Created file: \(fileURL.path)")
        } catch {
            print("Failed to create file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
