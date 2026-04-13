import Foundation
import RepositorySDK
import Testing
@testable import PRRadarConfigService

@Suite("RulePath")
struct RulePathTests {

    // MARK: - Encoding/Decoding

    @Test("encodes and decodes back to equal value") func roundTripEncoding() throws {
        // Arrange
        let rulePath = RulePath(name: "shared", path: "/Users/bill/shared-rules", isDefault: true)

        // Act
        let data = try JSONEncoder().encode(rulePath)
        let decoded = try JSONDecoder().decode(RulePath.self, from: data)

        // Assert
        #expect(decoded.id == rulePath.id)
        #expect(decoded.name == "shared")
        #expect(decoded.path == "/Users/bill/shared-rules")
        #expect(decoded.isDefault == true)
    }

    @Test("isDefault is false when not specified") func defaultIsDefaultIsFalse() {
        // Arrange & Act
        let rulePath = RulePath(name: "test", path: "rules")

        // Assert
        #expect(rulePath.isDefault == false)
    }
}
