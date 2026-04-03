import Foundation
import OSLog

struct GatewayConfigurationStore: Sendable {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "net.rychillie.Helm.gatewayConfiguration")
    {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> GatewayConfiguration? {
        guard let data = self.userDefaults.data(forKey: self.key) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(GatewayConfiguration.self, from: data)
        } catch {
            AppLogger.persistence.error("Failed to decode gateway configuration: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ configuration: GatewayConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        self.userDefaults.set(data, forKey: self.key)
    }

    func clear() {
        self.userDefaults.removeObject(forKey: self.key)
    }
}
