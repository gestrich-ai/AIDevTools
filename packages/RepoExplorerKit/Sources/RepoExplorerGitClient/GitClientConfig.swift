import Foundation

public struct GitClientConfig: Codable {
    public var repositories: [GitRepository]
    public var defaultRepository: String?
    public var lastSelectedRepository: String?

    public init(repositories: [GitRepository] = [], defaultRepository: String? = nil, lastSelectedRepository: String? = nil) {
        self.repositories = repositories
        self.defaultRepository = defaultRepository
        self.lastSelectedRepository = lastSelectedRepository
    }

    public static var configPath: String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDirectory)/.GitClient.json"
    }

    public static func load() -> GitClientConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
            return nil
        }

        return try? JSONDecoder().decode(GitClientConfig.self, from: data)
    }

    public static func tryLoad() -> GitClientConfig? {
        load()
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: Self.configPath))
    }

    public func getRepository(named name: String) -> GitRepository? {
        repositories.first { $0.name == name }
    }

    public func getDefaultRepository() -> GitRepository? {
        guard let defaultName = defaultRepository else {
            return repositories.first
        }
        return getRepository(named: defaultName)
    }

    public func getLastSelectedRepository() -> GitRepository? {
        if let lastSelected = lastSelectedRepository,
           let repo = getRepository(named: lastSelected) {
            return repo
        }
        return getDefaultRepository()
    }

    public mutating func setLastSelected(named name: String) {
        if repositories.contains(where: { $0.name == name }) {
            lastSelectedRepository = name
        }
    }

    public mutating func addRepository(_ repo: GitRepository) {
        // Remove existing repository with same name
        repositories.removeAll { $0.name == repo.name }
        repositories.append(repo)

        // Set as default if it's the first one
        if repositories.count == 1 {
            defaultRepository = repo.name
        }
    }

    public mutating func removeRepository(named name: String) {
        repositories.removeAll { $0.name == name }

        // Clear default if we removed it
        if defaultRepository == name {
            defaultRepository = repositories.first?.name
        }
    }

    public mutating func setDefault(named name: String) {
        if repositories.contains(where: { $0.name == name }) {
            defaultRepository = name
        }
    }

    public mutating func updateRepository(id: String, name: String, path: String, baseBranch: String, githubOrganization: String? = nil) {
        if let index = repositories.firstIndex(where: { $0.id == id }) {
            let oldName = repositories[index].name
            repositories[index].name = name
            repositories[index].path = path
            repositories[index].baseBranch = baseBranch
            repositories[index].githubOrganization = githubOrganization

            // Update default if we renamed the default repository
            if defaultRepository == oldName {
                defaultRepository = name
            }
        }
    }
}

public struct GitRepository: Codable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var path: String
    public var baseBranch: String
    public var githubOrganization: String?  // e.g., "foreflight" or "gestrich"

    public init(name: String, path: String, baseBranch: String = "origin/main", githubOrganization: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.path = path
        self.baseBranch = baseBranch
        self.githubOrganization = githubOrganization
    }

    public var displayName: String {
        name
    }

    public var displayPath: String {
        // Replace home directory with ~
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }
}
