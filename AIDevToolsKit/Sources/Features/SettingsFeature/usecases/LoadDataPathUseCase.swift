import DataPathsService
import Foundation
import UseCaseSDK

public struct LoadDataPathUseCase: UseCase {
    public init() {}

    public func run() -> URL {
        let prefs = AppPreferences()
        let path = prefs.dataPath() ?? AppPreferences.defaultDataPath
        prefs.setDataPath(path)
        return path
    }
}
