import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @Environment(SettingsModel.self) private var settingsModel
    @State private var photoErrorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    UserAvatarView(photoURL: settingsModel.userPhotoPath, size: 40)

                    Text("Photo")

                    Spacer()

                    Button("Choose…", action: selectPhoto)
                    Button {
                        do {
                            try settingsModel.updateUserPhotoPath(nil)
                            photoErrorMessage = nil
                        } catch {
                            photoErrorMessage = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(settingsModel.userPhotoPath == nil)
                }

                Text("Used for your avatar in chat views.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let photoErrorMessage {
                    Text(photoErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Profile")
            }

            Section {
                LabeledContent("Data Directory") {
                    HStack {
                        Text(settingsModel.dataPath.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.directoryURL = settingsModel.dataPath
                            if panel.runModal() == .OK, let url = panel.url {
                                settingsModel.updateDataPath(url)
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                    }
                }

                Text("Directory where repository configurations and eval output are stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Data Storage")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectPhoto() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try settingsModel.updateUserPhotoPath(url)
                photoErrorMessage = nil
            } catch {
                photoErrorMessage = error.localizedDescription
            }
        }
    }
}
