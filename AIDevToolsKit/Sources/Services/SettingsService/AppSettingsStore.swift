import Foundation

public struct AppSettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppSettings {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return AppSettings()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
