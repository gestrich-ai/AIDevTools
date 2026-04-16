import RepoExplorerFileTreeService
import SwiftUI

struct QuickFilePickerView: View {
    @Bindable var viewModel: DirectoryBrowserViewModel
    @Binding var isPresented: Bool

    @FocusState private var isSearchFieldFocused: Bool
    @State private var filteredFiles: [FileSystemItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var searchText: String = ""
    @State private var selectedFileID: FileSystemItem.ID?
    @State private var totalMatchCount = 0

    private static let lastSearchKey = "RepoExplorerUI.quickFilePicker.lastSearch"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFieldFocused)
                    .accessibilityIdentifier("repoExplorerQuickOpenSearchField")
                    .onSubmit {
                        if let file = filteredFiles.first(where: { $0.id == selectedFileID }) ?? filteredFiles.first {
                            selectFile(file)
                        }
                    }
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("repoExplorerQuickOpenCloseButton")
            }
            .padding()

            Divider()

            if !searchText.isEmpty && totalMatchCount > filteredFiles.count {
                HStack {
                    Text("Showing \(filteredFiles.count) of \(totalMatchCount) matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }

            if searchText.isEmpty {
                ContentUnavailableView(
                    "Search Files",
                    systemImage: "magnifyingglass",
                    description: Text("Type a filename or path fragment.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFiles.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredFiles, selection: $selectedFileID) { file in
                    Button {
                        selectFile(file)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Text(file.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(relativePath(for: file))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(file.id)
                }
                .listStyle(.plain)
                .accessibilityIdentifier("repoExplorerQuickOpenResults")
            }
        }
        .frame(width: 640, height: 420)
        .accessibilityIdentifier("repoExplorerQuickOpenSheet")
        .onAppear {
            searchText = UserDefaults.standard.string(forKey: Self.lastSearchKey) ?? ""
            if !searchText.isEmpty {
                performSearch(query: searchText)
            }
            isSearchFieldFocused = true
        }
        .onDisappear {
            UserDefaults.standard.set(searchText, forKey: Self.lastSearchKey)
            searchTask?.cancel()
        }
    }

    private func performSearch(query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            filteredFiles = []
            selectedFileID = nil
            totalMatchCount = 0
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }

            let searchResult = await viewModel.searchFiles(query: query, limit: 10)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                filteredFiles = searchResult.matches
                selectedFileID = searchResult.matches.first?.id
                totalMatchCount = searchResult.totalCount
            }
        }
    }

    private func selectFile(_ file: FileSystemItem) {
        viewModel.selectItem(file)
        isPresented = false
    }

    private func relativePath(for file: FileSystemItem) -> String {
        guard let rootPath = viewModel.currentRootPath else { return file.path }
        return file.relativePath(from: rootPath)
    }
}
