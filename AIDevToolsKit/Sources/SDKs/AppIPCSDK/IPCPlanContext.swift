import Foundation

public struct IPCPlanContext: Codable, Equatable, Sendable {
    public let completedPhases: [String]
    public let planFilePath: String
    public let planName: String

    public init(completedPhases: [String], planFilePath: String, planName: String) {
        self.completedPhases = completedPhases
        self.planFilePath = planFilePath
        self.planName = planName
    }
}
