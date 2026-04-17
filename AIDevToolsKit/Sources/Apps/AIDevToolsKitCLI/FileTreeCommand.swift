import ArgumentParser

struct FileTreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-tree",
        abstract: "Explore, index, and update repository file trees",
        subcommands: [
            FileTreeCreateFileCommand.self,
            FileTreeCreateFolderCommand.self,
            FileTreeDeleteCommand.self,
            FileTreeIndexCommand.self,
            FileTreeListCommand.self,
            FileTreeRenameCommand.self,
            FileTreeSearchCommand.self,
            FileTreeStatsCommand.self,
        ]
    )
}
