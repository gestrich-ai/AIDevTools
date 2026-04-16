import SwiftUI

public struct DirectoryTreeView: View {
    @Environment(DirectoryBrowserViewModel.self) private var viewModel

    let repoPath: String

    public init(repoPath: String) {
        self.repoPath = repoPath
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.rootItems) { item in
                    FileItemRow(item: item, viewModel: viewModel, level: 0)
                }
            }
            .padding(.vertical, 4)
        }
        .task(id: repoPath) {
            await viewModel.selectDirectory(url: URL(fileURLWithPath: repoPath))
        }
        .onDisappear {
            Task {
                await viewModel.stopMonitoring()
            }
        }
    }
}
