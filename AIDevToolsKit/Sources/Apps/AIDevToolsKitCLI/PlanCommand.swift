import ArgumentParser

struct PlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "markdown-planner",
        abstract: "Voice-driven plan generation and phased execution",
        subcommands: [PlanDeleteCommand.self, PlanExecuteCommand.self, PlanPlanCommand.self]
    )
}
