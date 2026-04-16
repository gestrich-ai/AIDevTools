import Foundation

public protocol MCPConfigurable: Sendable {
    func writeMCPConfig(binaryURL: URL)
}
