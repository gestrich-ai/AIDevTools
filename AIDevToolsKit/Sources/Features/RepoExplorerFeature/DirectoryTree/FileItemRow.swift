import FileTreeService
import SwiftUI

struct FileItemRow: View {
    @ObservedObject var item: FileSystemItem
    let viewModel: DirectoryBrowserViewModel
    let level: Int

    @State private var errorMessage: String?
    @State private var newName = ""
    @State private var showingCreateFileAlert = false
    @State private var showingCreateFolderAlert = false
    @State private var showingDeleteAlert = false
    @State private var showingRenameAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Spacer()
                    .frame(width: CGFloat(level * 16))

                if item.isDirectory {
                    Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                } else {
                    Spacer()
                        .frame(width: 16)
                }

                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isDirectory ? .blue : .secondary)

                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(viewModel.selectedItem?.id == item.id ? Color.accentColor.opacity(0.18) : .clear)
            .onAppear {
                if item.isDirectory {
                    viewModel.loadChildrenIfNeeded(for: item)
                }
            }
            .onTapGesture(count: 2) {
                if item.isDirectory {
                    viewModel.toggleExpansion(for: item)
                } else {
                    viewModel.selectItem(item)
                }
            }
            .onTapGesture {
                if item.isDirectory {
                    viewModel.toggleExpansion(for: item)
                } else {
                    viewModel.selectItem(item)
                }
            }
            .contextMenu {
                if item.isDirectory {
                    Button("Create File") {
                        newName = ""
                        showingCreateFileAlert = true
                    }

                    Button("Create Folder") {
                        newName = ""
                        showingCreateFolderAlert = true
                    }

                    Divider()
                }

                Button("Rename") {
                    newName = item.name
                    showingRenameAlert = true
                }

                Button("Delete", role: .destructive) {
                    showingDeleteAlert = true
                }
            }

            if item.isExpanded, let children = item.children, !children.isEmpty {
                ForEach(children) { child in
                    FileItemRow(item: child, viewModel: viewModel, level: level + 1)
                }
            }
        }
        .alert("Create File", isPresented: $showingCreateFileAlert) {
            TextField("File name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task {
                    do {
                        try await viewModel.createFile(in: item, name: newName)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the name for the new file.")
        }
        .alert("Create Folder", isPresented: $showingCreateFolderAlert) {
            TextField("Folder name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task {
                    do {
                        try await viewModel.createFolder(in: item, name: newName)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the name for the new folder.")
        }
        .alert("Rename", isPresented: $showingRenameAlert) {
            TextField("New name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task {
                    do {
                        try await viewModel.renameItem(item, to: newName)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the new name for '\(item.name)'.")
        }
        .alert("Delete", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await viewModel.deleteItem(item)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Delete '\(item.name)'? This cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
}
