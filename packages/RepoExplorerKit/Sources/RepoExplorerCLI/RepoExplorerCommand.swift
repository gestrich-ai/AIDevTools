import ArgumentParser
import Foundation

@main
struct RepoExplorerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repo-explorer",
        abstract: "Explore, index, and update repository file trees",
        subcommands: [
            RepoExplorerIndexCommand.self,
            RepoExplorerListCommand.self,
            RepoExplorerSearchCommand.self,
            RepoExplorerStatsCommand.self,
            RepoExplorerCreateFileCommand.self,
            RepoExplorerCreateFolderCommand.self,
            RepoExplorerDeleteCommand.self,
            RepoExplorerRenameCommand.self,
        ]
    )

    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}
