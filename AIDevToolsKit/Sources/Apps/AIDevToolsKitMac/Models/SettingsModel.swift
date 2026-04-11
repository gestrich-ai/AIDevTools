import Foundation
import SettingsFeature

@MainActor @Observable
final class SettingsModel {

    static let aiDevToolsRepoPathKey = "AIDevTools.aiDevToolsRepoPath"

    private(set) var aiDevToolsRepoPath: URL?
    private(set) var dataPath: URL

    init() {
        dataPath = LoadDataPathUseCase().run()
        if let storedPath = UserDefaults.standard.string(forKey: Self.aiDevToolsRepoPathKey) {
            aiDevToolsRepoPath = URL(fileURLWithPath: storedPath)
        }
    }

    func updateAIDevToolsRepoPath(_ newPath: URL?) {
        aiDevToolsRepoPath = newPath
        UserDefaults.standard.set(newPath?.path, forKey: Self.aiDevToolsRepoPathKey)
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
        SaveDataPathUseCase().run(path: newPath)
    }
}
