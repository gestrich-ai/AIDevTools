import Foundation

public struct SkillScanner: Sendable {

    public init() {}

    static let commandsDirectories = [".agents/commands", ".claude/commands"]
    static let skillsDirectories = [".agents/skills", ".claude/skills"]

    public func scanSkills(
        at repositoryPath: URL,
        globalCommandsDirectory: URL? = nil
    ) throws -> [SkillInfo] {
        var skillsByName: [String: SkillInfo] = [:]
        var visited: Set<String> = []

        // Skills directories (highest priority — scanned first, first wins)
        for relative in Self.skillsDirectories {
            let skillsDirectory = repositoryPath.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: skillsDirectory.path) else { continue }

            let resolved = skillsDirectory.resolvingSymlinksInPath()
            guard visited.insert(resolved.path).inserted else { continue }

            let contents = try FileManager.default.contentsOfDirectory(
                at: resolved,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            for item in contents {
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    let skillFile = item.appendingPathComponent("SKILL.md")
                    if FileManager.default.fileExists(atPath: skillFile.path) {
                        let name = item.lastPathComponent
                        if skillsByName[name] == nil {
                            let refs = findReferenceFiles(in: item)
                            skillsByName[name] = SkillInfo(name: name, path: item, referenceFiles: refs)
                        }
                    }
                } else if item.pathExtension == "md" {
                    let name = item.deletingPathExtension().lastPathComponent
                    if skillsByName[name] == nil {
                        skillsByName[name] = SkillInfo(name: name, path: item)
                    }
                }
            }
        }

        // Local commands directories (lower priority than skills)
        for relative in Self.commandsDirectories {
            let commandsDirectory = repositoryPath.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: commandsDirectory.path) else { continue }

            let resolved = commandsDirectory.resolvingSymlinksInPath()
            guard visited.insert(resolved.path).inserted else { continue }

            for info in scanCommandsDirectory(resolved) {
                if skillsByName[info.name] == nil {
                    skillsByName[info.name] = info
                }
            }
        }

        // Global commands directory (lowest priority)
        if let globalDir = globalCommandsDirectory,
           FileManager.default.fileExists(atPath: globalDir.path) {
            let resolved = globalDir.resolvingSymlinksInPath()
            if visited.insert(resolved.path).inserted {
                for info in scanCommandsDirectory(resolved) {
                    if skillsByName[info.name] == nil {
                        skillsByName[info.name] = info
                    }
                }
            }
        }

        return skillsByName.values.sorted { $0.name < $1.name }
    }

    private func scanCommandsDirectory(_ directory: URL) -> [SkillInfo] {
        let resolved = directory.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: resolved,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var results: [SkillInfo] = []
        let basePath = resolved.path + "/"

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "md" else { continue }
            let resolvedFile = fileURL.resolvingSymlinksInPath()
            let relativePath = resolvedFile.path.replacingOccurrences(of: basePath, with: "")
            let name = (relativePath as NSString).deletingPathExtension
            results.append(SkillInfo(name: name, path: resolvedFile))
        }

        return results
    }

    private func findReferenceFiles(in directory: URL) -> [SkillReferenceFile] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return items
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "SKILL.md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { SkillReferenceFile(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }
}
