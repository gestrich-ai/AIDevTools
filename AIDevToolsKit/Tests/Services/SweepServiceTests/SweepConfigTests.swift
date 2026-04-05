import Foundation
import Testing
@testable import SweepService

@Suite("SweepConfig")
struct SweepConfigTests {

    @Test("isDirectoryMode: true when filePattern ends with /")
    func isDirectoryModeForTrailingSlash() {
        #expect(SweepConfig(filePattern: "Sources/*/").isDirectoryMode == true)
        #expect(SweepConfig(filePattern: "Sources/**/*/").isDirectoryMode == true)
        #expect(SweepConfig(filePattern: "Sources/MyModule/").isDirectoryMode == true)
    }

    @Test("isDirectoryMode: false when filePattern does not end with /")
    func isNotDirectoryModeWithoutTrailingSlash() {
        #expect(SweepConfig(filePattern: "Sources/**/*.swift").isDirectoryMode == false)
        #expect(SweepConfig(filePattern: "Sources/*.swift").isDirectoryMode == false)
        #expect(SweepConfig(filePattern: "").isDirectoryMode == false)
    }
}
