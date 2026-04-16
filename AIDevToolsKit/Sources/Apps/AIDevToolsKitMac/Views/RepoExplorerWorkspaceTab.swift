import RepoExplorerFeature
import SwiftUI

struct RepoExplorerWorkspaceTab: View {
    let repoPath: String
    let viewModelFactory: @MainActor () -> DirectoryBrowserViewModel

    @State private var viewModel: DirectoryBrowserViewModel

    init(
        repoPath: String,
        viewModelFactory: @escaping @MainActor () -> DirectoryBrowserViewModel
    ) {
        self.repoPath = repoPath
        self.viewModelFactory = viewModelFactory
        _viewModel = State(initialValue: viewModelFactory())
    }

    var body: some View {
        RepoExplorerView(repoPath: repoPath, viewModel: viewModel)
            .task(id: repoPath) {
                await viewModel.selectDirectory(url: URL(fileURLWithPath: repoPath, isDirectory: true))
            }
            .onDisappear {
                Task {
                    await viewModel.stopMonitoring()
                }
            }
    }
}
