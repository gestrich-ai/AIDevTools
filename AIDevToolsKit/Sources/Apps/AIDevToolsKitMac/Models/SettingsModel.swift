import Foundation
import SettingsFeature

@MainActor @Observable
final class SettingsModel {

    private(set) var dataPath: URL

    init() {
        dataPath = LoadDataPathUseCase().run()
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
        SaveDataPathUseCase().run(path: newPath)
    }
}
