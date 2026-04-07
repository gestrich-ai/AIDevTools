import DataPathsService
import Foundation
import UseCaseSDK

public struct SaveDataPathUseCase: UseCase {
    public init() {}

    public func run(path: URL) {
        AppPreferences().setDataPath(path)
    }
}
