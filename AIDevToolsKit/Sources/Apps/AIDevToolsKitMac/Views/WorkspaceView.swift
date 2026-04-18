import Combine
import ProviderRegistryService
import RepoExplorerFeature
import RepositorySDK
import SwiftUI

struct WorkspaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceModel.self) var model

    let evalProviderRegistry: EvalProviderRegistry
    let repoExplorerViewModelFactory: @MainActor () -> DirectoryBrowserViewModel

    @State private var executionPanelModel = ExecutionPanelModel()
    @AppStorage(ExperimentalSettings.architecturePlannerKey) private var isArchitecturePlannerEnabled = false
    @AppStorage("selectedRepositoryID") private var storedRepoID: String = ""
    @AppStorage("selectedWorkspaceTab") private var selectedTab: String = "claudeChain"
    @State private var deepLinkWatcher = DeepLinkWatcher()
    @State private var selectedRepoID: UUID?

    private var isChatPanelSupportedTab: Bool {
        selectedTab == "claudeChain" || selectedTab == "plans"
    }

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
                tabContent(for: repo)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "folder",
                    description: Text("Choose a repository from the sidebar.")
                )
            }
        }
        .inspector(isPresented: Bindable(executionPanelModel).isVisible) {
            RightExecutionPanelView(
                tab: selectedTab,
                workingDirectory: model.selectedRepository?.path.path(percentEncoded: false) ?? ""
            )
            .id("\(selectedTab)-\(model.selectedRepository?.id.uuidString ?? "")")
            .environment(executionPanelModel)
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
        }
        .onChange(of: executionPanelModel.isVisible) { _, isVisible in
            savePanelVisibility(isVisible)
        }
        .onChange(of: selectedTab) { _, _ in
            restorePanelVisibility()
        }
        .onChange(of: model.selectedRepository?.id) { _, _ in
            restorePanelVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .credentialsDidChange)) { _ in
            appModel.applyCredentialChange(.anthropicAPIKey)
            appModel.applyCredentialChange(.githubToken)
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

    private func panelVisibilityKey(tab: String, repoID: UUID?) -> String {
        "chatPanelVisible_\(tab)_\(repoID?.uuidString ?? "none")"
    }

    private func savePanelVisibility(_ isVisible: Bool) {
        guard isChatPanelSupportedTab, let repo = model.selectedRepository else { return }

        let key = panelVisibilityKey(tab: selectedTab, repoID: repo.id)
        UserDefaults.standard.set(isVisible, forKey: key)
    }

    private func restorePanelVisibility() {
        guard isChatPanelSupportedTab, let repo = model.selectedRepository else {
            executionPanelModel.isVisible = false
            return
        }

        let key = panelVisibilityKey(tab: selectedTab, repoID: repo.id)
        executionPanelModel.isVisible = UserDefaults.standard.bool(forKey: key)
    }
}
