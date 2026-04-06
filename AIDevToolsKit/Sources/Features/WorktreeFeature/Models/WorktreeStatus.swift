import Foundation
import GitSDK

public struct WorktreeStatus: Identifiable, Sendable {
    public let info: WorktreeInfo
    public let hasUncommittedChanges: Bool

    public var id: UUID { info.id }
    public var name: String { info.name }
    public var branch: String { info.branch }
    public var isMain: Bool { info.isMain }
    public var path: String { info.path }
}
