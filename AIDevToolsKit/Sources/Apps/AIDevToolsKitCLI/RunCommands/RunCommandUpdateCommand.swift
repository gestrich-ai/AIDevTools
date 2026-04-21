import ArgumentParser
import Foundation
import RepositorySDK
import RunCommandFeature
import SettingsService

struct RunCommandUpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a run command in a repository"
    )

    @Argument(help: "UUID or path of the repository")
    var repo: String

    @Option(help: "UUID of the run command to update")
    var commandId: String

    @Option(help: "New display name")
    var name: String?

    @Option(help: "New shell command")
    var command: String?

    @Flag(help: "Mark as default (cannot unset — remove and re-add to change default)")
    var setDefault = false

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() throws {
        guard let commandUUID = UUID(uuidString: commandId) else {
            throw ValidationError("Invalid command UUID: \(commandId)")
        }
        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let store = settings.repositoryStore
        let repoConfig = try RunCommandCommand.resolveRepo(store: store, repoArg: repo)
        guard let existing = repoConfig.runCommands?.first(where: { $0.id == commandUUID }) else {
            throw ValidationError("Run command not found: \(commandId)")
        }
        let updated = RepoRunCommand(
            id: commandUUID,
            command: command ?? existing.command,
            isDefault: setDefault ? true : existing.isDefault,
            name: name ?? existing.name
        )
        let result = try UpdateRunCommandUseCase(store: store).run(repoID: repoConfig.id, command: updated)
        print("Updated run command '\(updated.name)' in \(result.name).")
    }

}
