import CredentialFeature
import CredentialService
import SwiftUI

struct CredentialManagementView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(CredentialModel.self) private var credentialModel
    @State private var selectedProfile: SelectedProfile?
    @State private var editingGitHubProfile: EditableGitHubProfile?
    @State private var editingAnthropicProfile: EditableAnthropicProfile?
    @State private var isAddingNew = false
    @State private var currentError: Error?
    @State private var profileToDelete: SelectedProfile?

    var body: some View {
        HSplitView {
            sidebarView
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Credential Error", isPresented: isErrorPresented, presenting: currentError) { _ in
            Button("OK") { currentError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(item: $editingGitHubProfile) { profile in
            GitHubCredentialEditSheet(profile: profile, isNew: isAddingNew) { updated in
                do {
                    guard let auth = updated.buildGitHubAuth() else { return }
                    try credentialModel.saveGitHubProfile(id: updated.profileName, auth: auth)
                    notifyCredentialChange(.githubToken)
                } catch {
                    currentError = error
                }
                isAddingNew = false
            } onCancel: {
                isAddingNew = false
            }
        }
        .sheet(item: $editingAnthropicProfile) { profile in
            AnthropicCredentialEditSheet(profile: profile, isNew: isAddingNew) { updated in
                do {
                    try credentialModel.saveAnthropicProfile(id: updated.profileName, apiKey: updated.apiKey)
                    notifyCredentialChange(.anthropicAPIKey)
                } catch {
                    currentError = error
                }
                isAddingNew = false
            } onCancel: {
                isAddingNew = false
            }
        }
        .confirmationDialog(
            "Delete Profile",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            presenting: profileToDelete
        ) { profile in
            Button("Delete", role: .destructive) {
                deleteProfile(profile)
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: { profile in
            switch profile {
            case .gitHub(let id):
                Text("Delete GitHub profile '\(id)'? This will remove the stored credential from Keychain.")
            case .anthropic(let id):
                Text("Delete Anthropic profile '\(id)'? This will remove the API key from Keychain.")
            }
        }
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            List(selection: $selectedProfile) {
                Section("GitHub Profiles") {
                    if credentialModel.gitHubProfiles.isEmpty {
                        Text("No profiles")
                            .foregroundStyle(.tertiary)
                            .tag(Optional<SelectedProfile>.none)
                    } else {
                        ForEach(credentialModel.gitHubProfiles) { profile in
                            Text(profile.id)
                                .tag(SelectedProfile.gitHub(profile.id))
                        }
                    }
                }

                Section("Anthropic Profiles") {
                    if credentialModel.anthropicProfiles.isEmpty {
                        Text("No profiles")
                            .foregroundStyle(.tertiary)
                            .tag(Optional<SelectedProfile>.none)
                    } else {
                        ForEach(credentialModel.anthropicProfiles) { profile in
                            Text(profile.id)
                                .tag(SelectedProfile.anthropic(profile.id))
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                Menu {
                    Button("GitHub Profile") {
                        isAddingNew = true
                        editingGitHubProfile = EditableGitHubProfile()
                    }
                    Button("Anthropic Profile") {
                        isAddingNew = true
                        editingAnthropicProfile = EditableAnthropicProfile()
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 14, height: 14)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26, height: 22)
                .accessibilityIdentifier("addCredentialButton")

                Button {
                    if let profile = selectedProfile {
                        profileToDelete = profile
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("deleteCredentialButton")
                .disabled(selectedProfile == nil)

                Spacer()
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedProfile {
        case .gitHub(let id):
            if let profile = credentialModel.gitHubProfiles.first(where: { $0.id == id }) {
                GitHubProfileDetailView(profile: profile) {
                    isAddingNew = false
                    editingGitHubProfile = EditableGitHubProfile(from: profile)
                }
            } else {
                noSelectionView
            }
        case .anthropic(let id):
            if let profile = credentialModel.anthropicProfiles.first(where: { $0.id == id }) {
                AnthropicProfileDetailView(profile: profile) {
                    isAddingNew = false
                    editingAnthropicProfile = EditableAnthropicProfile(from: profile)
                }
            } else {
                noSelectionView
            }
        case nil:
            noSelectionView
        }
    }

    private var noSelectionView: some View {
        ContentUnavailableView(
            "Select a Profile",
            systemImage: "key",
            description: Text("Choose a credential profile from the list.")
        )
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { currentError != nil },
            set: { if !$0 { currentError = nil } }
        )
    }

    private func deleteProfile(_ profile: SelectedProfile) {
        switch profile {
        case .gitHub(let id):
            credentialModel.removeGitHubProfile(id: id)
            notifyCredentialChange(.githubToken)
        case .anthropic(let id):
            credentialModel.removeAnthropicProfile(id: id)
            notifyCredentialChange(.anthropicAPIKey)
        }
        selectedProfile = nil
    }

    private func notifyCredentialChange(_ type: CredentialType) {
        appModel.applyCredentialChange(type)
        NotificationCenter.default.post(name: .credentialsDidChange, object: nil)
    }
}

// MARK: - Selection Type

enum SelectedProfile: Hashable {
    case anthropic(String)
    case gitHub(String)
}

// MARK: - Editable Types

enum GitHubAuthMode: String, CaseIterable {
    case app = "GitHub App"
    case token = "Personal Access Token"
}

struct EditableGitHubProfile: Identifiable {
    let id = UUID()
    var appId: String = ""
    var authMode: GitHubAuthMode = .token
    var githubToken: String = ""
    var installationId: String = ""
    var privateKeyPEM: String = ""
    var profileName: String = ""

    init() {}

    init(from profile: GitHubCredentialProfile) {
        profileName = profile.id
        switch profile.auth {
        case .token(let t):
            authMode = .token
            githubToken = t
        case .app(let aId, let iId, let pem):
            authMode = .app
            appId = aId
            installationId = iId
            privateKeyPEM = pem
        }
    }

    func buildGitHubAuth() -> GitHubAuth? {
        switch authMode {
        case .token:
            guard !githubToken.isEmpty else { return nil }
            return .token(githubToken)
        case .app:
            guard !appId.isEmpty, !installationId.isEmpty, !privateKeyPEM.isEmpty else { return nil }
            return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKeyPEM)
        }
    }

    var canSave: Bool {
        !profileName.isEmpty && buildGitHubAuth() != nil
    }
}

struct EditableAnthropicProfile: Identifiable {
    let id = UUID()
    var apiKey: String = ""
    var profileName: String = ""

    init() {}

    init(from profile: AnthropicCredentialProfile) {
        profileName = profile.id
        apiKey = profile.apiKey
    }

    var canSave: Bool {
        !profileName.isEmpty && !apiKey.isEmpty
    }
}

// MARK: - Detail Views

private struct GitHubProfileDetailView: View {
    let profile: GitHubCredentialProfile
    let onEdit: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    Text(profile.id)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Auth Type") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(authTypeLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Edit") {
                    onEdit()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var authTypeLabel: String {
        switch profile.auth {
        case .token: "Personal Access Token"
        case .app: "GitHub App"
        }
    }
}

private struct AnthropicProfileDetailView: View {
    let profile: AnthropicCredentialProfile
    let onEdit: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    Text(profile.id)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("API Key") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Stored")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Edit") {
                    onEdit()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Edit Sheets

private struct GitHubCredentialEditSheet: View {
    @State var profile: EditableGitHubProfile
    let isNew: Bool
    let onSave: (EditableGitHubProfile) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add GitHub Profile" : "Edit GitHub Profile")
                .font(.title2)
                .bold()

            LabeledContent("Profile Name") {
                TextField("e.g. work, personal", text: $profile.profileName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            LabeledContent("Auth Type") {
                Picker("", selection: $profile.authMode) {
                    ForEach(GitHubAuthMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            switch profile.authMode {
            case .token:
                LabeledContent("Token") {
                    SecureField("ghp_...", text: $profile.githubToken)
                        .textFieldStyle(.roundedBorder)
                }
            case .app:
                LabeledContent("App ID") {
                    TextField("123456", text: $profile.appId)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Installation ID") {
                    TextField("12345678", text: $profile.installationId)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Private Key PEM") {
                    TextEditor(text: $profile.privateKeyPEM)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.3))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(profile)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!profile.canSave)
            }
        }
        .padding()
        .frame(width: 480)
    }
}

private struct AnthropicCredentialEditSheet: View {
    @State var profile: EditableAnthropicProfile
    let isNew: Bool
    let onSave: (EditableAnthropicProfile) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Anthropic Profile" : "Edit Anthropic Profile")
                .font(.title2)
                .bold()

            LabeledContent("Profile Name") {
                TextField("e.g. default", text: $profile.profileName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            LabeledContent("API Key") {
                SecureField("sk-ant-...", text: $profile.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(profile)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!profile.canSave)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
