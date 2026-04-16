import RepoExplorerDataPathsService
import RepoExplorerFileTreeService
import RepoExplorerFeature

@MainActor
func makeRepoExplorerViewModelFactory() throws -> @MainActor () -> DirectoryBrowserViewModel {
    let dataPathsService = try RepoExplorerDataPathsService.DataPathsService()

    return {
        DirectoryBrowserViewModel(
            fileTreeService: FileTreeService(dataPathsService: dataPathsService)
        )
    }
}
