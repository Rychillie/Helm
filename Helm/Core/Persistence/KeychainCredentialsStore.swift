import Foundation
import Security

struct KeychainCredentialsStore: CredentialsStore, Sendable {
    private let service: String

    init(service: String = "net.rychillie.Helm.gatewayCredentials") {
        self.service = service
    }

    func loadSecret(for configuration: GatewayConfiguration) throws -> String? {
        let query = self.baseQuery(for: configuration).merging(
            [kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne],
            uniquingKeysWith: { _, new in new })

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func saveSecret(_ secret: String?, for configuration: GatewayConfiguration) throws {
        let trimmedSecret = secret?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedSecret, !trimmedSecret.isEmpty else {
            try self.removeSecret(for: configuration)
            return
        }

        let data = Data(trimmedSecret.utf8)
        let query = self.baseQuery(for: configuration)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
    }

    func removeSecret(for configuration: GatewayConfiguration) throws {
        let status = SecItemDelete(self.baseQuery(for: configuration) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func baseQuery(for configuration: GatewayConfiguration) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: "\(configuration.endpoint.absoluteString)|\(configuration.authMode.rawValue)",
        ]
    }
}
