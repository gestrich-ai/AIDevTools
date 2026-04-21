import RepositorySDK
import SwiftUI

struct RunCommandToolbarButton: View {
    let repo: RepositoryConfiguration
    let commandModel: RunCommandModel

    @AppStorage private var lastCommandID: String

    init(repo: RepositoryConfiguration, commandModel: RunCommandModel) {
        self.repo = repo
        self.commandModel = commandModel
        _lastCommandID = AppStorage(wrappedValue: "", "runCommandID_\(repo.id.uuidString)")
    }

    private var commands: [RepoRunCommand] {
        repo.runCommands ?? []
    }

    private var activeCommand: RepoRunCommand? {
        if !lastCommandID.isEmpty,
           let id = UUID(uuidString: lastCommandID),
           let match = commands.first(where: { $0.id == id }) {
            return match
        }
        return commands.first(where: { $0.isDefault }) ?? commands.first
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: runActive) {
                runButtonLabel
            }
            .help(activeCommand.map { "Run: \($0.name)" } ?? "No run commands configured — add them in Repositories settings")
            .disabled(activeCommand == nil || isRunning)

            if commands.count > 1 {
                Menu {
                    ForEach(commands) { command in
                        Button {
                            lastCommandID = command.id.uuidString
                            commandModel.run(command.command, in: repo.path)
                        } label: {
                            if command.id == activeCommand?.id {
                                Label(command.name, systemImage: "checkmark")
                            } else {
                                Text(command.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
                .disabled(isRunning)
            }
        }
    }

    @ViewBuilder
    private var runButtonLabel: some View {
        switch commandModel.state {
        case .idle:
            Image(systemName: "play.fill")
        case .running:
            ProgressView()
                .controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var isRunning: Bool {
        if case .running = commandModel.state { return true }
        return false
    }

    private func runActive() {
        guard let command = activeCommand else { return }
        commandModel.run(command.command, in: repo.path)
    }
}
