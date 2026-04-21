import ArgumentParser
import Foundation
import RepositorySDK

struct RunCommandCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-commands",
        abstract: "Manage and execute run commands for a repository",
        subcommands: [
            RunCommandAddCommand.self,
            RunCommandListCommand.self,
            RunCommandRemoveCommand.self,
            RunCommandRunCommand.self,
            RunCommandUpdateCommand.self,
        ]
    )
}

extension RunCommandCommand {
    static func resolveRepo(store: RepositoryStore, repoArg: String) throws -> RepositoryConfiguration {
        if let uuid = UUID(uuidString: repoArg) {
            guard let match = try store.find(byID: uuid) else {
                throw ValidationError("Repository not found: \(repoArg)")
            }
            return match
        }
        let url = URL(filePath: repoArg, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath))
        guard let match = try store.find(byPath: url) else {
            throw ValidationError("Repository not found at path: \(url.path())")
        }
        return match
    }
}
