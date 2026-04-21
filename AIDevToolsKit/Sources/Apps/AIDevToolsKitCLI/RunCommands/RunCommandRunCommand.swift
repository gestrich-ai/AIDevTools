import ArgumentParser
import Foundation
import RepositorySDK
import RunCommandFeature
import SettingsService

struct RunCommandRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Execute a run command for a repository"
    )

    @Argument(help: "UUID or path of the repository")
    var repo: String

    @Option(help: "Name or UUID of the command to run (defaults to the default command)")
    var commandName: String?

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() async throws {
        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let repoConfig = try RunCommandCommand.resolveRepo(store: settings.repositoryStore, repoArg: repo)
        let commands = repoConfig.runCommands ?? []
        guard !commands.isEmpty else {
            throw ValidationError("No run commands configured for \(repoConfig.name). Use 'run-commands add' to add one.")
        }
        let cmd = try resolveCommand(from: commands)
        print("Running '\(cmd.name)' in \(repoConfig.path.path(percentEncoded: false))...")
        print("$ \(cmd.command)")
        print()
        let output = try await ExecuteRunCommandUseCase().run(command: cmd.command, in: repoConfig.path)
        if !output.isEmpty {
            print(output)
        }
        print("\nDone.")
    }

    private func resolveCommand(from commands: [RepoRunCommand]) throws -> RepoRunCommand {
        guard let nameOrID = commandName else {
            if let defaultCmd = commands.first(where: { $0.isDefault }) ?? commands.first {
                return defaultCmd
            }
            throw ValidationError("No commands available.")
        }
        if let uuid = UUID(uuidString: nameOrID),
           let match = commands.first(where: { $0.id == uuid }) {
            return match
        }
        if let match = commands.first(where: { $0.name.lowercased() == nameOrID.lowercased() }) {
            return match
        }
        throw ValidationError("Command not found: \(nameOrID). Use 'run-commands list' to see available commands.")
    }

}
