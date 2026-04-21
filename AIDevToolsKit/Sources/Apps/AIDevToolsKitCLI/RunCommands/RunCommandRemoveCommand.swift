import ArgumentParser
import Foundation
import RepositorySDK
import RunCommandFeature
import SettingsService

struct RunCommandRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a run command from a repository"
    )

    @Argument(help: "UUID or path of the repository")
    var repo: String

    @Option(help: "UUID of the run command to remove")
    var commandId: String

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() throws {
        guard let commandUUID = UUID(uuidString: commandId) else {
            throw ValidationError("Invalid command UUID: \(commandId)")
        }
        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let store = settings.repositoryStore
        let repoConfig = try RunCommandCommand.resolveRepo(store: store, repoArg: repo)
        _ = try RemoveRunCommandUseCase(store: store).run(repoID: repoConfig.id, commandID: commandUUID)
        print("Removed run command \(commandId) from \(repoConfig.name).")
    }

}
