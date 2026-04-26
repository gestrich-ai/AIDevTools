import DataPathsService
import Foundation

extension DataPathsService {
    static func fromCLI(dataPath: String?) throws -> DataPathsService {
        let resolved = ResolveDataPathUseCase().resolve(explicit: dataPath)
        let service = try DataPathsService(rootPath: resolved.path)
        try MigrateDataPathsUseCase(dataPathsService: service).run()
        return service
    }
}
