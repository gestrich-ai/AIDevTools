import ArchitecturePlannerService
import DataPathsService
import Foundation

extension DataPathsService {
    static func makeArchPlannerStore(dataPath: String?, repoName: String) throws -> ArchitecturePlannerStore {
        let resolved = ResolveDataPathUseCase().resolve(explicit: dataPath)
        let service = try DataPathsService(rootPath: resolved.path)
        try MigrateDataPathsUseCase(dataPathsService: service).run()
        let baseDir = try service.path(for: .architecturePlanner)
        let archDir = baseDir.appendingPathComponent(repoName)
        try FileManager.default.createDirectory(at: archDir, withIntermediateDirectories: true, attributes: nil)
        return try ArchitecturePlannerStore(directoryURL: archDir)
    }
}
