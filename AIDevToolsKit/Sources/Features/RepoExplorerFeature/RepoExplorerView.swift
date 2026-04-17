import FileTreeService
import SwiftUI

public struct RepoExplorerView: View {
    @State private var isQuickPickerPresented = false
    @State private var viewModel: DirectoryBrowserViewModel

    private let repoPath: String

    public init(repoPath: String, viewModel: DirectoryBrowserViewModel) {
        self.repoPath = repoPath
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                DirectoryTreeView(repoPath: repoPath)
                    .environment(viewModel)
                    .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 420, maxHeight: .infinity)

            Divider()

            VStack(spacing: 0) {
                previewHeader
                Divider()
                preview
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isQuickPickerPresented) {
            QuickFilePickerView(viewModel: viewModel, isPresented: $isQuickPickerPresented)
        }
        .background(
            Button("") {
                isQuickPickerPresented = true
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .hidden()
        )
        .accessibilityIdentifier("repoExplorerRoot")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(URL(fileURLWithPath: repoPath).lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("repoExplorerName")

            Text(repoPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("repoExplorerPath")

            if viewModel.isIndexing {
                ProgressView(viewModel.indexingProgress)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await viewModel.refreshDirectory() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh — delete cache and rescan")
                .disabled(viewModel.isIndexing)
                .accessibilityIdentifier("repoExplorerRefreshButton")

                Button {
                    isQuickPickerPresented = true
                } label: {
                    Label("Quick Open", systemImage: "magnifyingglass")
                }
                .help("Quick Open (Command-Shift-O)")
                .accessibilityIdentifier("repoExplorerQuickOpenButton")
            }
        }
    }

    private var previewHeader: some View {
        HStack {
            Text(viewModel.selectedItem?.name ?? "Preview")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if let selectedItem = viewModel.selectedItem {
                Text(selectedItem.relativePath(from: repoPath))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var preview: some View {
        if let selectedItem = viewModel.selectedItem {
            if selectedItem.isDirectory {
                ContentUnavailableView(
                    selectedItem.name,
                    systemImage: "folder",
                    description: Text("Select a file to preview its contents.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(viewModel.fileContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .accessibilityIdentifier("repoExplorerPreviewText")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        } else {
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text",
                description: Text("Choose a file from the tree or press Command-Shift-O to quick open.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
