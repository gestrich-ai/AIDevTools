import SwiftUI

enum WorkspaceStyle {
    static let sidebarWidth: CGFloat = 250
}

struct WorkspaceSidebar<Content: View>: View {
    let onAdd: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button { onAdd() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
        .frame(width: WorkspaceStyle.sidebarWidth)
    }
}
