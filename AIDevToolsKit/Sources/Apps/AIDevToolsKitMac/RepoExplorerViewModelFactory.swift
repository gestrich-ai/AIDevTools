import DataPathsService
import FileTreeService
import RepoExplorerFeature

@MainActor
func makeRepoExplorerViewModelFactory(
    dataPathsService: DataPathsService
) -> @MainActor () -> DirectoryBrowserViewModel {
    return {
        DirectoryBrowserViewModel(
            fileTreeService: FileTreeService(dataPathsService: dataPathsService)
        )
    }
}
