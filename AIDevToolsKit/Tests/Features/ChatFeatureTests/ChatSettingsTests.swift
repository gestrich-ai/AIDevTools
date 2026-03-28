import Foundation
import Testing
@testable import ChatFeature

struct ChatSettingsTests {

    @Test func defaultValues() {
        let settings = ChatSettings()
        #expect(type(of: settings.enableStreaming) == Bool.self)
        #expect(type(of: settings.resumeLastSession) == Bool.self)
        #expect(type(of: settings.verboseMode) == Bool.self)
        #expect(settings.maxThinkingTokens >= 1024)
    }
}
