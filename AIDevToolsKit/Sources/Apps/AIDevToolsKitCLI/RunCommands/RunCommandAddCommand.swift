import ArgumentParser
import Foundation
import RepositorySDK
import RunCommandFeature
import SettingsService

struct RunCommandAddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a run command to a repository"
    )

    @Argument(help: "UUID or path of the repository")
    var repo: String

    @Option(help: "Display name for the command")
    var name: String

    @Option(help: "Shell command to execute")
    var command: String

    @Flag(help: "Mark this as the default run command")
    var isDefault = false

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() throws {
        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let store = settings.repositoryStore
        let repoConfig = try RunCommandCommand.resolveRepo(store: store, repoArg: repo)
        let cmd = RepoRunCommand(command: command, isDefault: isDefault, name: name)
        let updated = try AddRunCommandUseCase(store: store).run(repoID: repoConfig.id, command: cmd)
        print("Added run command '\(cmd.name)' to \(updated.name).")
        print("  ID:      \(cmd.id)")
        print("  Command: \(cmd.command)")
    }

}
