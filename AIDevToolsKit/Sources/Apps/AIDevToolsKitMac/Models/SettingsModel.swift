import DataPathsService
import Foundation
import SettingsFeature

@MainActor @Observable
final class SettingsModel {

    private let loadDataPathUseCase: LoadDataPathUseCase
    private let preferences: AppPreferences
    private let saveDataPathUseCase: SaveDataPathUseCase
    private(set) var aiDevToolsRepoPath: URL?
    private(set) var dataPath: URL

    init(
        loadDataPathUseCase: LoadDataPathUseCase = LoadDataPathUseCase(),
        preferences: AppPreferences = AppPreferences(),
        saveDataPathUseCase: SaveDataPathUseCase = SaveDataPathUseCase()
    ) {
        self.loadDataPathUseCase = loadDataPathUseCase
        self.preferences = preferences
        self.saveDataPathUseCase = saveDataPathUseCase
        dataPath = loadDataPathUseCase.run()
        aiDevToolsRepoPath = preferences.aiDevToolsRepoPath()
    }

    func updateAIDevToolsRepoPath(_ newPath: URL?) {
        aiDevToolsRepoPath = newPath
        preferences.setAIDevToolsRepoPath(newPath)
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
        saveDataPathUseCase.run(path: newPath)
    }
}
