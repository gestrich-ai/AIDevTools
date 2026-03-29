import Foundation

public struct CodeChangeContext: Sendable {
    public let workingDirectory: String?
    public let targetFiles: [String]
    public let environmentVars: [String: String]

    public init(
        workingDirectory: String?,
        targetFiles: [String],
        environmentVars: [String: String]
    ) {
        self.workingDirectory = workingDirectory
        self.targetFiles = targetFiles
        self.environmentVars = environmentVars
    }

    /// Empty context for backward compatibility during migration
    public static var empty: CodeChangeContext {
        CodeChangeContext(
            workingDirectory: nil,
            targetFiles: [],
            environmentVars: [:]
        )
    }
}