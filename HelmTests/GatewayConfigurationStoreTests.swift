import Foundation
import Testing

@testable import Helm

struct GatewayConfigurationStoreTests {
    @Test
    func savesAndLoadsConfiguration() throws {
        let suiteName = "GatewayConfigurationStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GatewayConfigurationStore(userDefaults: defaults, key: "gateway")
        let configuration = GatewayConfiguration(
            endpoint: try #require(URL(string: "ws://127.0.0.1:18789")),
            displayName: "Local Gateway",
            timeoutSeconds: 45,
            authMode: .sharedToken)

        try store.save(configuration)

        #expect(store.load() == configuration)
    }

    @Test
    func keychainCredentialsRoundTrip() throws {
        let store = KeychainCredentialsStore(service: "HelmTests.\(UUID().uuidString)")
        let configuration = GatewayConfiguration(
            endpoint: try #require(URL(string: "ws://127.0.0.1:18789")),
            displayName: nil,
            timeoutSeconds: 30,
            authMode: .sharedToken)

        try store.saveSecret("secret-token", for: configuration)
        #expect(try store.loadSecret(for: configuration) == "secret-token")

        try store.removeSecret(for: configuration)
        #expect(try store.loadSecret(for: configuration) == nil)
    }
}
