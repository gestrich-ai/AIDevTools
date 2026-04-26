import ArgumentParser
import ClaudeChainCLI
import Foundation
import Logging
#if os(macOS)
import CLIMacCommands
#endif

@main
struct AIDevToolsKit: AsyncParsableCommand {
    nonisolated(unsafe) static var bootstrapped = false

    static let configuration = CommandConfiguration(
        commandName: "ai-dev-tools-kit",
        abstract: "Developer tools for AI-assisted workflows",
        subcommands: subcommandTypes
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

    private static var subcommandTypes: [any ParsableCommand.Type] {
        var commands: [any ParsableCommand.Type] = [
            ChatCommand.self, ClaudeChainCLI.self, ConfigCommand.self, CredentialsCommand.self, EvalsCommand.self, LogsCommand.self, PlanCommand.self, PRRadarCommand.self, ReposCommand.self, RunCommandCommand.self, SkillsCommand.self, SweepCommand.self, WorktreeCommand.self,
        ]
        #if os(macOS)
        commands += CLIMacSubcommands.all
        #endif
        return commands
    }

    @Option(name: .long, help: "Log level: trace, debug, info, notice, warning, error, critical")
    var logLevel: Logger.Level = .info

    mutating func validate() throws {
        guard !Self.bootstrapped else { return }
        CLICompositionRoot.preServiceSetup(logLevel: logLevel)
        Self.bootstrapped = true
    }

}

extension Logger.Level: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
