import ArgumentParser
import Foundation
import RepositorySDK
import SettingsService

struct RunCommandListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List run commands for a repository"
    )

    @Argument(help: "UUID or path of the repository")
    var repo: String

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() throws {
        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let repoConfig = try RunCommandCommand.resolveRepo(store: settings.repositoryStore, repoArg: repo)
        let commands = repoConfig.runCommands ?? []
        if commands.isEmpty {
            print("No run commands configured for \(repoConfig.name).")
            return
        }
        print("Run commands for \(repoConfig.name) (\(repoConfig.id)):")
        for cmd in commands {
            let defaultMark = cmd.isDefault ? " [default]" : ""
            print("  \(cmd.id)  \(cmd.name)\(defaultMark)")
            print("    \(cmd.command)")
        }
    }

}
