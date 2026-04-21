import DataPathsService
import Foundation
import SettingsFeature
import SettingsService

@MainActor @Observable
final class SettingsModel {

    private let loadDataPathUseCase: LoadDataPathUseCase
    private let preferences: AppPreferences
    private let saveDataPathUseCase: SaveDataPathUseCase
    private let settingsService: SettingsService
    private(set) var aiDevToolsRepoPath: URL?
    private(set) var dataPath: URL
    private(set) var userPhotoPath: URL?

    init(
        loadDataPathUseCase: LoadDataPathUseCase = LoadDataPathUseCase(),
        preferences: AppPreferences = AppPreferences(),
        saveDataPathUseCase: SaveDataPathUseCase = SaveDataPathUseCase(),
        settingsService: SettingsService
    ) throws {
        self.loadDataPathUseCase = loadDataPathUseCase
        self.preferences = preferences
        self.saveDataPathUseCase = saveDataPathUseCase
        self.settingsService = settingsService
        dataPath = loadDataPathUseCase.run()
        aiDevToolsRepoPath = preferences.aiDevToolsRepoPath()
        userPhotoPath = try settingsService.loadUserPhotoURL()
    }

    func updateAIDevToolsRepoPath(_ newPath: URL?) {
        aiDevToolsRepoPath = newPath
        preferences.setAIDevToolsRepoPath(newPath)
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
        saveDataPathUseCase.run(path: newPath)
    }

    func updateUserPhotoPath(_ newPath: URL?) throws {
        if let newPath {
            userPhotoPath = try settingsService.saveUserPhoto(from: newPath)
        } else {
            try settingsService.removeUserPhoto()
            userPhotoPath = nil
        }
    }
}
