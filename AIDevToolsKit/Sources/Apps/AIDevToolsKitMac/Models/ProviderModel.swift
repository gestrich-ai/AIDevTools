import Foundation
import ProviderRegistryService

extension Notification.Name {
    static let credentialsDidChange = Notification.Name("credentialsDidChange")
}

@MainActor @Observable
final class ProviderModel {
    private(set) var providerRegistry: ProviderRegistry
    private let registrySource: @Sendable () -> ProviderRegistry

    init(registrySource: @escaping @Sendable () -> ProviderRegistry) {
        self.registrySource = registrySource
        self.providerRegistry = registrySource()
    }

    func refreshProviders() {
        self.providerRegistry = registrySource()
    }
}
