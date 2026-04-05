/// Domain model representing a ClaudeChain project
import Foundation

/// Domain model representing a ClaudeChain project with its paths and metadata
public struct Project {
    public let name: String
    public let basePath: String

    /// Initialize a Project
    ///
    /// - Parameters:
    ///   - name: Project name
    ///   - basePath: Base path for the project directory
    public init(name: String, basePath: String) {
        self.name = name
        self.basePath = basePath
    }
    
    /// Path to configuration.yml file
    public var configPath: String {
        return "\(basePath)/configuration.yml"
    }
    
    /// Path to spec.md file
    public var specPath: String {
        return "\(basePath)/spec.md"
    }
    
    /// Path to pr-template.md file
    public var prTemplatePath: String {
        return "\(basePath)/pr-template.md"
    }

    /// Path to review.md file
    public var reviewPath: String { "\(basePath)/review.md" }

    /// Path to metadata JSON file in claudechain-metadata branch
    public var metadataFilePath: String {
        return "\(name).json"
    }
    
    /// Factory: Extract project from config path
    ///
    /// - Parameter configPath: Path like 'claude-chain/my-project/configuration.yml'
    /// - Returns: Project instance
    public static func fromConfigPath(_ configPath: String) -> Project {
        let url = URL(fileURLWithPath: configPath)
        let basePath = url.deletingLastPathComponent().path
        let projectName = URL(fileURLWithPath: basePath).lastPathComponent
        return Project(name: projectName, basePath: basePath)
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