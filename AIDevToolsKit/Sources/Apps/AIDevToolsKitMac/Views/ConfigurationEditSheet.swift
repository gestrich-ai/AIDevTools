import PRRadarConfigService
import RepositorySDK
import SwiftUI

struct ConfigurationEditSheet: View {
    @State var config: RepositoryConfiguration
    @State private var nameText: String
    @State private var repoPathText: String
    @State private var casesDirectoryText: String
    @State private var completedDirectoryText: String
    @State private var proposedDirectoryText: String
    @State private var anthropicProfileIdText: String
    @State private var githubProfileIdText: String
    @State private var descriptionText: String
    @State private var recentFocusText: String
    @State private var skillsText: String
    @State private var architectureDocsText: String
    @State private var verificationCommandsText: String
    @State private var verificationNotesText: String
    @State private var prBaseBranchText: String
    @State private var prBranchNamingText: String
    @State private var prTemplateText: String
    @State private var prNotesText: String
    @State private var prradarRulePaths: [RulePath]
    @State private var prradarDiffSource: DiffSource
    @State private var runCommandsState: [RepoRunCommand]
    @FocusState private var focusedRunCommandID: UUID?
    let isNew: Bool
    let onSave: (RepositoryConfiguration, String?, String?, String?) -> Void
    let onSavePRRadarSettings: ((PRRadarRepoSettings) -> Void)?
    let onCancel: () -> Void
    @Environment(CredentialModel.self) private var credentialModel
    @Environment(\.dismiss) private var dismiss

    init(
        config: RepositoryConfiguration,
        casesDirectory: String?,
        completedDirectory: String?,
        proposedDirectory: String?,
        prradarSettings: PRRadarRepoSettings? = nil,
        isNew: Bool,
        onSave: @escaping (RepositoryConfiguration, String?, String?, String?) -> Void,
        onSavePRRadarSettings: ((PRRadarRepoSettings) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.config = config
        self.isNew = isNew
        self.onSave = onSave
        self.onSavePRRadarSettings = onSavePRRadarSettings
        self.onCancel = onCancel
        _nameText = State(initialValue: config.name)
        _repoPathText = State(initialValue: isNew ? "" : config.path.path(percentEncoded: false))
        _casesDirectoryText = State(initialValue: casesDirectory ?? "")
        _completedDirectoryText = State(initialValue: completedDirectory ?? "")
        _proposedDirectoryText = State(initialValue: proposedDirectory ?? "")
        _anthropicProfileIdText = State(initialValue: config.anthropicCredentialProfileId ?? "")
        _githubProfileIdText = State(initialValue: config.githubCredentialProfileId ?? "")
        _descriptionText = State(initialValue: config.description ?? "")
        _recentFocusText = State(initialValue: config.recentFocus ?? "")
        _skillsText = State(initialValue: (config.skills ?? []).joined(separator: "\n"))
        _architectureDocsText = State(initialValue: (config.architectureDocs ?? []).joined(separator: "\n"))
        _verificationCommandsText = State(initialValue: (config.verification?.commands ?? []).joined(separator: "\n"))
        _verificationNotesText = State(initialValue: config.verification?.notes ?? "")
        _prBaseBranchText = State(initialValue: config.pullRequest?.baseBranch ?? PullRequestConfig.defaultBaseBranch)
        _prBranchNamingText = State(initialValue: config.pullRequest?.branchNamingConvention ?? PullRequestConfig.defaultBranchNamingConvention)
        _prTemplateText = State(initialValue: config.pullRequest?.template ?? "")
        _prNotesText = State(initialValue: config.pullRequest?.notes ?? "")
        _prradarRulePaths = State(initialValue: prradarSettings?.rulePaths ?? [])
        _prradarDiffSource = State(initialValue: prradarSettings?.diffSource ?? .git)
        _runCommandsState = State(initialValue: config.runCommands ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "Add Repository" : "Edit Repository")
                .font(.title2)
                .bold()
                .padding([.horizontal, .top])

            Form {
                Section("General") {
                    LabeledContent("Name") {
                        TextField("my-repo", text: $nameText)
                            .textFieldStyle(.roundedBorder)
                    }

                    pathField(label: "Repo Path", text: $repoPathText, placeholder: "/path/to/repo")

                    LabeledContent("Description") {
                        TextField("Brief description of this repository", text: $descriptionText)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("GitHub Profile") {
                        Picker("", selection: $githubProfileIdText) {
                            Text("None").tag("")
                            ForEach(credentialModel.gitHubProfiles) { profile in
                                Text(profile.id).tag(profile.id)
                            }
                        }
                    }

                    LabeledContent("Anthropic Profile") {
                        Picker("", selection: $anthropicProfileIdText) {
                            Text("None").tag("")
                            ForEach(credentialModel.anthropicProfiles) { profile in
                                Text(profile.id).tag(profile.id)
                            }
                        }
                    }
                }

                Section("Chains") {
                    LabeledContent("Recent Focus") {
                        TextField("What you're currently working on", text: $recentFocusText)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Skills") {
                        multilineField(text: $skillsText, placeholder: "One skill per line")
                    }
                    LabeledContent("Architecture Docs") {
                        multilineField(text: $architectureDocsText, placeholder: "One path per line, relative to repo root")
                    }
                    LabeledContent("Verification Commands") {
                        multilineField(text: $verificationCommandsText, placeholder: "One command per line")
                    }
                    LabeledContent("Verification Notes") {
                        TextField("Optional verification notes", text: $verificationNotesText)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Run Commands") {
                    runCommandsSection
                }

                Section("Evals") {
                    pathField(label: "Cases Directory", text: $casesDirectoryText, placeholder: "Optional — relative or absolute path")
                }

                Section("Plans") {
                    pathField(label: "Proposed Plans", text: $proposedDirectoryText, placeholder: "Optional — defaults to docs/proposed")
                    pathField(label: "Completed Plans", text: $completedDirectoryText, placeholder: "Optional — defaults to docs/completed")

                    Text("Directories can be relative to the repo path, absolute, or use ~.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("PR Radar") {
                    rulePathsSection
                    LabeledContent("Diff Source") {
                        Picker("", selection: $prradarDiffSource) {
                            ForEach(DiffSource.allCases, id: \.self) { source in
                                Text(source.displayName).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                Section("Pull Requests") {
                    LabeledContent("Base Branch") {
                        TextField("main", text: $prBaseBranchText)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Branch Naming") {
                        TextField("feature/description", text: $prBranchNamingText)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Template") {
                        TextField("Optional — e.g. .github/pull_request_template.md", text: $prTemplateText)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Notes") {
                        TextField("Optional PR notes", text: $prNotesText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveRepository()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(repoPathText.isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 550, maxWidth: 550, minHeight: 400, idealHeight: 600, maxHeight: 700)
    }

    private func saveRepository() {
        let repoURL = URL(filePath: repoPathText)
        let finalName = nameText.isEmpty ? repoURL.lastPathComponent : nameText
        let cases = casesDirectoryText.isEmpty ? nil : casesDirectoryText
        let proposed = proposedDirectoryText.isEmpty ? nil : proposedDirectoryText
        let completed = completedDirectoryText.isEmpty ? nil : completedDirectoryText

        let skills = parseLines(skillsText)
        let archDocs = parseLines(architectureDocsText)
        let verifyCommands = parseLines(verificationCommandsText)

        let verification: Verification? = verifyCommands.isEmpty
            ? nil
            : Verification(commands: verifyCommands, notes: verificationNotesText.isEmpty ? nil : verificationNotesText)

        let pullRequest = PullRequestConfig.from(
            baseBranch: prBaseBranchText,
            branchNamingConvention: prBranchNamingText,
            template: prTemplateText,
            notes: prNotesText
        )

        let runCommands = runCommandsState.filter { !$0.command.isEmpty }

        let updated = RepositoryConfiguration(
            id: config.id,
            path: repoURL,
            name: finalName,
            anthropicCredentialProfileId: anthropicProfileIdText.isEmpty ? nil : anthropicProfileIdText,
            architectureDocs: archDocs.isEmpty ? nil : archDocs,
            description: descriptionText.isEmpty ? nil : descriptionText,
            githubCredentialProfileId: githubProfileIdText.isEmpty ? nil : githubProfileIdText,
            pullRequest: pullRequest,
            recentFocus: recentFocusText.isEmpty ? nil : recentFocusText,
            runCommands: runCommands.isEmpty ? nil : runCommands,
            skills: skills.isEmpty ? nil : skills,
            verification: verification
        )
        onSave(updated, cases, completed, proposed)

        if let onSavePRRadarSettings {
            let settings = PRRadarRepoSettings(
                rulePaths: prradarRulePaths,
                diffSource: prradarDiffSource
            )
            onSavePRRadarSettings(settings)
        }

        dismiss()
    }

    private func parseLines(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var runCommandsSection: some View {
        LabeledContent("Commands") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($runCommandsState) { $cmd in
                    runCommandRow($cmd)
                }

                Button {
                    let isFirst = runCommandsState.isEmpty
                    runCommandsState.append(RepoRunCommand(command: "", isDefault: isFirst, name: ""))
                } label: {
                    Label("Add Command", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func runCommandRow(_ cmd: Binding<RepoRunCommand>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Name", text: cmd.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                TextField("bash -c ...", text: cmd.command)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRunCommandID, equals: cmd.wrappedValue.id)
                    .layoutPriority(1)

                Toggle("Default", isOn: Binding(
                    get: { cmd.wrappedValue.isDefault },
                    set: { newValue in
                        if newValue {
                            for i in runCommandsState.indices {
                                runCommandsState[i].isDefault = runCommandsState[i].id == cmd.wrappedValue.id
                            }
                        } else {
                            cmd.wrappedValue.isDefault = false
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                Button(role: .destructive) {
                    runCommandsState.removeAll { $0.id == cmd.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }

            if focusedRunCommandID != cmd.wrappedValue.id, !cmd.wrappedValue.command.isEmpty {
                Text(cmd.wrappedValue.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .truncationMode(.middle)
            }
        }
    }

    private var rulePathsSection: some View {
        LabeledContent("Rule Paths") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($prradarRulePaths) { $rulePath in
                    rulePathRow($rulePath)
                }

                Button {
                    prradarRulePaths.append(RulePath.makeNew(existingCount: prradarRulePaths.count, isDefault: prradarRulePaths.isEmpty))
                } label: {
                    Label("Add Rule Path", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func rulePathRow(_ rulePath: Binding<RulePath>) -> some View {
        HStack(spacing: 6) {
            TextField("Name", text: rulePath.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)

            TextField("Path", text: rulePath.path)
                .textFieldStyle(.roundedBorder)

            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    rulePath.wrappedValue.path = url.path
                }
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)

            Toggle("Default", isOn: Binding(
                get: { rulePath.wrappedValue.isDefault },
                set: { newValue in
                    if newValue {
                        for i in prradarRulePaths.indices {
                            prradarRulePaths[i].isDefault = prradarRulePaths[i].id == rulePath.wrappedValue.id
                        }
                    } else {
                        rulePath.wrappedValue.isDefault = false
                    }
                }
            ))
            .toggleStyle(.checkbox)

            Button(role: .destructive) {
                prradarRulePaths.removeAll { $0.id == rulePath.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func multilineField(text: Binding<String>, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(.body)
            .frame(height: 48)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
    }

    private func pathField(label: String, text: Binding<String>, placeholder: String) -> some View {
        LabeledContent(label) {
            HStack {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        text.wrappedValue = url.path
                    }
                } label: {
                    Image(systemName: "folder")
                }
            }
        }
    }
}
