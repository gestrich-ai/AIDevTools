import Foundation
import RepositorySDK
import SkillScannerSDK
import UseCaseSDK

public struct LoadSkillsUseCase: UseCase {
    private let scanner: SkillScanner
    private let globalCommandsDirectory: URL?

    public init(
        scanner: SkillScanner = SkillScanner(),
        globalCommandsDirectory: URL? = SkillScanner.defaultGlobalCommandsDirectory
    ) {
        self.scanner = scanner
        self.globalCommandsDirectory = globalCommandsDirectory
    }

    public func run(options: RepositoryConfiguration) async throws -> [SkillInfo] {
        let scanner = self.scanner
        let globalDir = globalCommandsDirectory
        return try await Task.detached {
            try scanner.scanSkills(at: options.path, globalCommandsDirectory: globalDir)
        }.value
    }
}
