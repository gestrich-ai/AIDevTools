import Foundation
import UseCaseSDK
import os

public struct MigrateDataPathsUseCase: UseCase {
    private static let logger = Logger(subsystem: "com.aidevtools", category: "Migration")

    private let dataPathsService: DataPathsService
    private let oldArchPlannerRoot: URL
    private let fileManager: FileManager

    public init(
        dataPathsService: DataPathsService,
        oldArchPlannerRoot: URL = URL.homeDirectory.appending(path: ".ai-dev-tools"),
        fileManager: FileManager = .default
    ) {
        self.dataPathsService = dataPathsService
        self.oldArchPlannerRoot = oldArchPlannerRoot
        self.fileManager = fileManager
    }

    public func run() throws {
        try migrateSettingsFile(name: "repositories.json", to: .repositories)
        try migrateArchitecturePlannerData()
        try migrateFeatureSettingsIntoRepositories()
        try migrateAnthropicSessions()
    }

    private func migrateSettingsFile(name: String, to servicePath: ServicePath) throws {
        let oldFile = dataPathsService.rootPath.appending(path: name)
        guard fileManager.fileExists(atPath: oldFile.path) else { return }

        let newDir = try dataPathsService.path(for: servicePath)
        let newFile = newDir.appending(path: name)

        guard !fileManager.fileExists(atPath: newFile.path) else {
            Self.logger.info("Skipping \(name): already exists at new location")
            return
        }

        try fileManager.copyItem(at: oldFile, to: newFile)
        Self.logger.info("Migrated \(name) to \(newFile.path)")
    }

    private func migrateFeatureSettingsIntoRepositories() throws {
        let repositoriesFile = dataPathsService.rootPath
            .appending(path: "repositories")
            .appending(path: "repositories.json")
        guard fileManager.fileExists(atPath: repositoriesFile.path) else { return }

        guard let repositoriesData = fileManager.contents(atPath: repositoriesFile.path),
              var repos = try JSONSerialization.jsonObject(with: repositoriesData) as? [[String: Any]] else {
            return
        }

        var indexByRepoId: [String: Int] = [:]
        for (i, repo) in repos.enumerated() {
            if let id = repo["id"] as? String {
                indexByRepoId[id] = i
            }
        }

        var didChange = false

        let prradarFile = dataPathsService.rootPath
            .appending(path: "prradar/settings/prradar-settings.json")
        if fileManager.fileExists(atPath: prradarFile.path),
           let data = fileManager.contents(atPath: prradarFile.path),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for var entry in entries {
                guard let repoIdString = entry["repoId"] as? String,
                      let index = indexByRepoId[repoIdString] else { continue }
                entry.removeValue(forKey: "repoId")
                repos[index]["prradar"] = entry
                didChange = true
            }
            try fileManager.removeItem(at: prradarFile)
            Self.logger.info("Migrated prradar settings into repositories.json")
        }

        let evalFile = dataPathsService.rootPath
            .appending(path: "eval/settings/eval-settings.json")
        if fileManager.fileExists(atPath: evalFile.path),
           let data = fileManager.contents(atPath: evalFile.path),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for var entry in entries {
                guard let repoIdString = entry["repoId"] as? String,
                      let index = indexByRepoId[repoIdString] else { continue }
                entry.removeValue(forKey: "repoId")
                repos[index]["eval"] = entry
                didChange = true
            }
            try fileManager.removeItem(at: evalFile)
            Self.logger.info("Migrated eval settings into repositories.json")
        }

        let planFile = dataPathsService.rootPath
            .appending(path: "plan/settings/plan-settings.json")
        if fileManager.fileExists(atPath: planFile.path),
           let data = fileManager.contents(atPath: planFile.path),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for var entry in entries {
                guard let repoIdString = entry["repoId"] as? String,
                      let index = indexByRepoId[repoIdString] else { continue }
                entry.removeValue(forKey: "repoId")
                repos[index]["planner"] = entry
                didChange = true
            }
            try fileManager.removeItem(at: planFile)
            Self.logger.info("Migrated plan settings into repositories.json")
        }

        guard didChange else { return }

        let updatedData = try JSONSerialization.data(withJSONObject: repos, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: repositoriesFile, options: .atomic)
        Self.logger.info("Wrote merged repositories.json")
    }

    private func migrateAnthropicSessions() throws {
        let oldSessions = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".aidevtools/anthropic/sessions")
        guard fileManager.fileExists(atPath: oldSessions.path) else { return }

        let newSessions = dataPathsService.rootPath.appending(path: ServicePath.anthropicSessions.relativePath)
        guard !fileManager.fileExists(atPath: newSessions.path) else {
            Self.logger.info("Skipping anthropic sessions migration: already exists at new location")
            return
        }

        try fileManager.createDirectory(at: newSessions.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: oldSessions, to: newSessions)
        Self.logger.info("Migrated anthropic sessions to \(newSessions.path)")
    }

    private func migrateArchitecturePlannerData() throws {
        guard fileManager.fileExists(atPath: oldArchPlannerRoot.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: oldArchPlannerRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for repoDir in contents {
            let values = try repoDir.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let repoName = repoDir.lastPathComponent
            let oldArchDir = repoDir.appending(path: "architecture-planner")
            guard fileManager.fileExists(atPath: oldArchDir.path) else { continue }

            let newArchDir = try dataPathsService.path(for: "architecture-planner", subdirectory: repoName)

            let archContents = try fileManager.contentsOfDirectory(
                at: oldArchDir,
                includingPropertiesForKeys: nil
            )
            for item in archContents {
                let dest = newArchDir.appending(path: item.lastPathComponent)
                guard !fileManager.fileExists(atPath: dest.path) else {
                    Self.logger.info("Skipping \(item.lastPathComponent) for \(repoName): already exists")
                    continue
                }
                try fileManager.copyItem(at: item, to: dest)
                Self.logger.info("Migrated architecture-planner/\(item.lastPathComponent) for \(repoName)")
            }
        }
    }
}
