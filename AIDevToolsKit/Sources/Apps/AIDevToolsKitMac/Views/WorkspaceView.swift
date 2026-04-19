import Combine
import ProviderRegistryService
import RepoExplorerFeature
import RepositorySDK
import SwiftUI

struct WorkspaceView: View {
    private enum ExecutionPanelWidthMode: String {
        case side
        case wide
    }

    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceModel.self) var model

    let evalProviderRegistry: EvalProviderRegistry
    let repoExplorerViewModelFactory: @MainActor () -> DirectoryBrowserViewModel

    @State private var executionPanelModel = ExecutionPanelModel()
    @AppStorage(ExperimentalSettings.architecturePlannerKey) private var isArchitecturePlannerEnabled = false
    @AppStorage("executionPanelWidthMode") private var executionPanelWidthMode = ExecutionPanelWidthMode.side.rawValue
    @AppStorage("workspaceExecutionPanelWidth") private var storedExecutionPanelWidth: Double = 360
    @AppStorage("selectedRepositoryID") private var storedRepoID: String = ""
    @AppStorage("selectedWorkspaceTab") private var selectedTab: String = "claudeChain"
    @State private var deepLinkWatcher = DeepLinkWatcher()
    @State private var panelDragStartWidth: CGFloat?
    @State private var selectedRepoID: UUID?

    private var isChatPanelSupportedTab: Bool {
        selectedTab == "claudeChain" || selectedTab == "plans"
    }

    private static let executionPanelMinWidth: CGFloat = 320
    private static let executionPanelMaxWidth: CGFloat = 900
    private static let executionPanelResizeHandleWidth: CGFloat = 8
    private static let workspaceDetailMinWidth: CGFloat = 420

    var body: some View {
        NavigationSplitView {
            List(model.repositories, selection: $selectedRepoID) { repo in
                Text(repo.name)
            }
            .navigationTitle("Repositories")
            .onChange(of: selectedRepoID) { _, newValue in
                storedRepoID = newValue?.uuidString ?? ""
                if let id = newValue, let repo = model.repositories.first(where: { $0.id == id }) {
                    Task { await model.selectRepository(repo) }
                }
            }
        } detail: {
            if let repo = model.selectedRepository {
                detailContent(for: repo)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "folder",
                    description: Text("Choose a repository from the sidebar.")
                )
            }
        }
        .task {
            deepLinkWatcher.start()
            model.load()
            if let id = UUID(uuidString: storedRepoID),
               let repo = model.repositories.first(where: { $0.id == id }) {
                selectedRepoID = id
                await model.selectRepository(repo)
            }
            restorePanelVisibility()
            applyExecutionPanelWidthPreset()
        }
        .onChange(of: executionPanelModel.isVisible) { _, isVisible in
            savePanelVisibility(isVisible)
        }
        .onChange(of: executionPanelWidthMode) { _, _ in
            applyExecutionPanelWidthPreset()
        }
        .onChange(of: selectedTab) { _, _ in
            restorePanelVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .credentialsDidChange)) { _ in
            appModel.applyCredentialChange(.anthropicAPIKey)
            appModel.applyCredentialChange(.githubToken)
        }
    }

    @ViewBuilder
    private func detailContent(for repo: RepositoryConfiguration) -> some View {
        if isChatPanelSupportedTab && executionPanelModel.isVisible {
            GeometryReader { geometry in
                let panelWidth = clampedExecutionPanelWidth(for: geometry.size.width)

                HStack(spacing: 0) {
                    tabContent(for: repo)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    executionPanelResizeHandle(totalWidth: geometry.size.width)

                    RightExecutionPanelView(
                        tab: selectedTab,
                        workingDirectory: repo.path.path(percentEncoded: false)
                    )
                    .id("\(selectedTab)-\(repo.path.path(percentEncoded: false))")
                    .frame(width: panelWidth)
                    .environment(executionPanelModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            tabContent(for: repo)
        }
    }

    @ViewBuilder
    private func tabContent(for repo: RepositoryConfiguration) -> some View {
        TabView(selection: $selectedTab) {
            if isArchitecturePlannerEnabled {
                ArchitecturePlannerView(repository: repo)
                    .tabItem { Label("Architecture", systemImage: "building.columns") }
                    .tag("architecture")
                    .id("architecture")
            }

            ClaudeChainView(repository: repo)
                .tabItem { Label("Chains", systemImage: "link") }
                .tag("claudeChain")
                .id("claudeChain")

            PlansContainer(repository: repo)
                .tabItem { Label("Plans", systemImage: "doc.text") }
                .tag("plans")
                .id("plans")

            PRRadarContentView(isActive: selectedTab == "prradar", repository: repo)
                .tabItem { Label("PR Radar", systemImage: "eye") }
                .tag("prradar")
                .id("prradar")

            SkillsContainer(repository: repo, evalProviderRegistry: evalProviderRegistry)
                .tabItem { Label("Skills", systemImage: "star") }
                .tag("skills")
                .id("skills")

            RepoExplorerWorkspaceTab(
                repoPath: repo.path.path(percentEncoded: false),
                viewModelFactory: repoExplorerViewModelFactory
            )
                .tabItem { Label("Repo Explorer", systemImage: "sidebar.squares.left") }
                .tag("repoExplorer")
                .id("repoExplorer")

            WorktreesView(isActive: selectedTab == "worktrees")
                .tabItem { Label("Worktrees", systemImage: "square.split.2x1") }
                .tag("worktrees")
                .id("worktrees")
        }
        .toolbar {
            if selectedTab == "claudeChain" || selectedTab == "plans" {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { executionPanelModel.isVisible.toggle() }) {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help("Toggle Panel")
                }
            }
        }
        .environment(executionPanelModel)
    }

    private func executionPanelResizeHandle(totalWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: Self.executionPanelResizeHandleWidth)
            .overlay {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let startWidth = panelDragStartWidth ?? clampedExecutionPanelWidth(for: totalWidth)
                        if panelDragStartWidth == nil {
                            panelDragStartWidth = startWidth
                        }
                        storedExecutionPanelWidth = clampedExecutionPanelWidth(
                            startWidth - value.translation.width,
                            totalWidth: totalWidth
                        )
                    }
                    .onEnded { _ in
                        panelDragStartWidth = nil
                    }
            )
    }

    private func applyExecutionPanelWidthPreset() {
        switch ExecutionPanelWidthMode(rawValue: executionPanelWidthMode) ?? .side {
        case .side:
            storedExecutionPanelWidth = 360
        case .wide:
            storedExecutionPanelWidth = 720
        }
    }

    private func clampedExecutionPanelWidth(for totalWidth: CGFloat) -> CGFloat {
        clampedExecutionPanelWidth(CGFloat(storedExecutionPanelWidth), totalWidth: totalWidth)
    }

    private func clampedExecutionPanelWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let maxWidth = min(
            Self.executionPanelMaxWidth,
            max(Self.executionPanelMinWidth, totalWidth - Self.workspaceDetailMinWidth)
        )
        return min(max(proposedWidth, Self.executionPanelMinWidth), maxWidth)
    }

    private func panelVisibilityKey(tab: String) -> String {
        "chatPanelVisible_\(tab)"
    }

    private func savePanelVisibility(_ isVisible: Bool) {
        guard isChatPanelSupportedTab else { return }

        let key = panelVisibilityKey(tab: selectedTab)
        UserDefaults.standard.set(isVisible, forKey: key)
    }

    private func restorePanelVisibility() {
        guard isChatPanelSupportedTab else {
            executionPanelModel.isVisible = false
            return
        }

        let key = panelVisibilityKey(tab: selectedTab)
        executionPanelModel.isVisible = UserDefaults.standard.bool(forKey: key)
    }
}
