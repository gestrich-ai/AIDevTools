import ArgumentParser

public struct CLIMacSubcommands {
    public static var all: [any ParsableCommand.Type] {
        [ArchPlannerCommand.self, FileTreeCommand.self, MCPCommand.self]
    }
}
