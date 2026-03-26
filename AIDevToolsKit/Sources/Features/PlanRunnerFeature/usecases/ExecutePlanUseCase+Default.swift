import ClaudeCLISDK
import Foundation
import GitSDK

extension ExecutePlanUseCase {
    public init(
        completedDirectory: URL? = nil,
        dataPath: URL,
        gitClient: GitClient = GitClient()
    ) {
        self.init(
            client: ClaudeCLIClient(),
            completedDirectory: completedDirectory,
            dataPath: dataPath,
            gitClient: gitClient
        )
    }
}
