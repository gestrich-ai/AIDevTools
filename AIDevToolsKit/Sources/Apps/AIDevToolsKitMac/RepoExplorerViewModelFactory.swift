import RepoExplorerDataPathsService
import RepoExplorerFileTreeService
import RepoExplorerUI

@MainActor
func makeRepoExplorerViewModelFactory() throws -> @MainActor () -> DirectoryBrowserViewModel {
    let dataPathsService = try RepoExplorerDataPathsService.DataPathsService()

    return {
        DirectoryBrowserViewModel(
            fileTreeService: FileTreeService(dataPathsService: dataPathsService)
        )
    }
}
