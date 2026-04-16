import Foundation

/// Confidence level for ownership attribution
public enum OwnershipConfidence: String, Codable, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"
}
