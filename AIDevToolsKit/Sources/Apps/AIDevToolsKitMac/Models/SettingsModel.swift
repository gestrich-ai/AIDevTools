import DataPathsService
import Foundation
import SettingsFeature

@MainActor @Observable
final class SettingsModel {

    private let preferences = AppPreferences()
    private(set) var aiDevToolsRepoPath: URL?
    private(set) var dataPath: URL

    init() {
        dataPath = LoadDataPathUseCase().run()
        aiDevToolsRepoPath = preferences.aiDevToolsRepoPath()
    }

    func updateAIDevToolsRepoPath(_ newPath: URL?) {
        aiDevToolsRepoPath = newPath
        preferences.setAIDevToolsRepoPath(newPath)
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
        SaveDataPathUseCase().run(path: newPath)
    }
}
