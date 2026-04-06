import Foundation

public struct WorktreeInfo: Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let branch: String
    public let isMain: Bool

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
