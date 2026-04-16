import Foundation
import Observation

@Observable
public final class ChatSettings {
    private enum Keys {
        static let enableStreaming = "chat.enableStreaming"
        static let maxThinkingTokens = "chat.maxThinkingTokens"
        static let resumeLastSession = "chat.resumeLastSession"
        static let verboseMode = "chat.verboseMode"
    }

    public var enableStreaming: Bool
    public var maxThinkingTokens: Int
    public var resumeLastSession: Bool
    public var verboseMode: Bool

    public init() {
        self.enableStreaming = UserDefaults.standard.object(forKey: Keys.enableStreaming) as? Bool ?? true
        self.maxThinkingTokens = UserDefaults.standard.object(forKey: Keys.maxThinkingTokens) as? Int ?? 2048
        self.resumeLastSession = UserDefaults.standard.object(forKey: Keys.resumeLastSession) as? Bool ?? true
        self.verboseMode = UserDefaults.standard.object(forKey: Keys.verboseMode) as? Bool ?? false
    }

    public func updateEnableStreaming(_ enabled: Bool) {
        enableStreaming = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.enableStreaming)
    }

    public func updateMaxThinkingTokens(_ tokens: Int) {
        let clampedTokens = max(tokens, 1024)
        maxThinkingTokens = clampedTokens
        UserDefaults.standard.set(clampedTokens, forKey: Keys.maxThinkingTokens)
    }

    public func updateResumeLastSession(_ enabled: Bool) {
        resumeLastSession = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.resumeLastSession)
    }

    public func updateVerboseMode(_ enabled: Bool) {
        verboseMode = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.verboseMode)
    }
}
