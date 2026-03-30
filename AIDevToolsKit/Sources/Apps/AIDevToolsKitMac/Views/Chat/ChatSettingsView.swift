import SwiftUI

struct ChatSettingsView: View {
    @Environment(ChatModel.self) private var chatModel: ChatModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Streaming", isOn: Binding(
                        get: { chatModel.settings.enableStreaming },
                        set: { chatModel.settings.enableStreaming = $0 }
                    ))
                    .help("Show response as it's being generated")

                    Toggle("Resume Last Session", isOn: Binding(
                        get: { chatModel.settings.resumeLastSession },
                        set: { chatModel.settings.resumeLastSession = $0 }
                    ))
                    .help("Automatically resume the most recent session when the app starts")
                } header: {
                    Text("Conversation")
                }

                Section {
                    Toggle("Verbose Mode", isOn: Binding(
                        get: { chatModel.settings.verboseMode },
                        set: { chatModel.settings.verboseMode = $0 }
                    ))
                    .help("Show thinking process and intermediate steps")

                    HStack {
                        Text("Max Thinking Tokens")
                        Spacer()
                        TextField("Tokens", value: Binding(
                            get: { chatModel.settings.maxThinkingTokens },
                            set: { chatModel.settings.maxThinkingTokens = max($0, 1024) }
                        ), format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    }
                    .help("Maximum tokens for thinking output (minimum: 1024)")
                } header: {
                    Text("Thinking & Reasoning")
                } footer: {
                    Text("Verbose mode shows internal reasoning. Thinking tokens must be at least 1024.")
                }

                Section {
                    LabeledContent("Working Directory") {
                        Text(chatModel.workingDirectory)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    LabeledContent("Provider") {
                        Text(chatModel.providerDisplayName)
                            .font(.caption)
                    }
                } header: {
                    Text("Context")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Chat Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
