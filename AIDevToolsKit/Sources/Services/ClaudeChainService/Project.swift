import Foundation

public struct Project {
    public let name: String
    public let basePath: String

    public init(name: String, basePath: String) {
        self.name = name
        self.basePath = basePath
    }

    public init(name: String) {
        self.name = name
        self.basePath = "claude-chain/\(name)"
    }

    public var configPath: String { "\(basePath)/configuration.yml" }
    public var prTemplatePath: String { "\(basePath)/pr-template.md" }
    public var reviewPath: String { "\(basePath)/review.md" }
    public var specPath: String { "\(basePath)/spec.md" }

    /// Path to metadata JSON file in claudechain-metadata branch
    public var metadataFilePath: String {
        return "\(name).json"
    }
    
    /// Factory: Extract project from config path
    ///
    /// - Parameter configPath: Path like 'claude-chain/my-project/configuration.yml'
    /// - Returns: Project instance
    public static func fromConfigPath(_ configPath: String) -> Project {
        let basePath = (configPath as NSString).deletingLastPathComponent
        let projectName = (basePath as NSString).lastPathComponent
        return Project(name: projectName, basePath: basePath)
    }

    /// Factory: Extract project from a claude-chain branch name.
    ///
    /// - Parameter branchName: Branch name like 'claude-chain-my-project-a1b2c3d4'
    /// - Returns: Project instance, or nil if branch name format is invalid
    public static func fromBranchName(_ branchName: String) -> Project? {
        guard let info = BranchInfo.fromBranchName(branchName) else { return nil }
        return Project(name: info.projectName)
    }

    /// Discover all chain projects in a directory by looking for subdirectories that contain spec.md.
    ///
    /// - Parameter baseDir: Directory to scan (e.g. "claude-chain/")
    /// - Returns: Projects sorted by name
    public static func findAll(baseDir: String) -> [Project] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: baseDir) else { return [] }
        return entries
            .sorted()
            .compactMap { name -> Project? in
                var isDir: ObjCBool = false
                let path = (baseDir as NSString).appendingPathComponent(name)
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
                let specPath = (path as NSString).appendingPathComponent("spec.md")
                guard fm.fileExists(atPath: specPath) else { return nil }
                return Project(name: name, basePath: path)
            }
    }
}

extension Project: Equatable {}
extension Project: Hashable {}

extension Project: CustomStringConvertible {
    /// String representation for debugging
    public var description: String {
        return "Project(name: '\(name)', basePath: '\(basePath)')"
    }
}