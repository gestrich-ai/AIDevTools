import DataPathsService
import Foundation
import RepositorySDK

public struct SettingsService: Sendable {
    public let appSettingsDirectory: URL
    public let appSettingsStore: AppSettingsStore
    public let repositoryStore: RepositoryStore

    public init(dataPathsService: DataPathsService) throws {
        let appSettingsDirectory = try dataPathsService.path(for: .appSettings)
        let appSettingsFile = appSettingsDirectory.appending(path: "app-settings.json")
        let repositoriesFile = try dataPathsService.path(for: .repositories)
            .appending(path: "repositories.json")
        self.appSettingsDirectory = appSettingsDirectory
        self.appSettingsStore = AppSettingsStore(fileURL: appSettingsFile)
        self.repositoryStore = RepositoryStore(repositoriesFile: repositoriesFile)
    }

    public func loadAppSettings() throws -> AppSettings {
        try appSettingsStore.load()
    }

    public func loadUserPhotoURL() throws -> URL? {
        let fileManager = FileManager.default
        let settings = try loadAppSettings()
        guard let filename = settings.userPhotoFilename else { return nil }
        let url = appSettingsDirectory.appending(path: filename)
        guard fileManager.fileExists(atPath: url.path()) else { return nil }
        return url
    }

    public func saveUserPhoto(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        var settings = try loadAppSettings()
        let data = try Data(contentsOf: sourceURL)

        if let existingFilename = settings.userPhotoFilename {
            let existingURL = appSettingsDirectory.appending(path: existingFilename)
            if fileManager.fileExists(atPath: existingURL.path()) {
                try fileManager.removeItem(at: existingURL)
            }
        }

        let pathExtension = sourceURL.pathExtension.isEmpty ? "img" : sourceURL.pathExtension.lowercased()
        let targetFilename = "user-photo.\(pathExtension)"
        let targetURL = appSettingsDirectory.appending(path: targetFilename)
        try data.write(to: targetURL, options: .atomic)

        settings.userPhotoFilename = targetFilename
        try appSettingsStore.save(settings)
        return targetURL
    }

    public func removeUserPhoto() throws {
        let fileManager = FileManager.default
        var settings = try loadAppSettings()

        if let filename = settings.userPhotoFilename {
            let fileURL = appSettingsDirectory.appending(path: filename)
            if fileManager.fileExists(atPath: fileURL.path()) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        settings.userPhotoFilename = nil
        try appSettingsStore.save(settings)
    }

    public func loadRepositories() throws -> [RepositoryConfiguration] {
        try repositoryStore.loadAll()
    }

    public func addRepository(_ repository: RepositoryConfiguration) throws {
        try repositoryStore.add(repository)
    }

    public func updateRepository(_ repository: RepositoryConfiguration) throws {
        try repositoryStore.update(repository)
    }

    public func removeRepository(id: UUID) throws {
        try repositoryStore.remove(id: id)
    }

    public func findRepository(byID id: UUID) throws -> RepositoryConfiguration? {
        try repositoryStore.find(byID: id)
    }

    public func findRepository(byPath path: URL) throws -> RepositoryConfiguration? {
        try repositoryStore.find(byPath: path)
    }
}
