import ArgumentParser

struct EvalsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evals",
        abstract: "Skill Evaluator — run and inspect eval cases against AI providers",
        subcommands: [
            EvalsClearCommand.self,
            EvalsListCommand.self,
            EvalsRunCommand.self,
            EvalsShowOutputCommand.self,
        ]
    )
}
