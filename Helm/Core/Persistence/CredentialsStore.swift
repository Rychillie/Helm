import Foundation

protocol CredentialsStore: Sendable {
    func loadSecret(for configuration: GatewayConfiguration) throws -> String?
    func saveSecret(_ secret: String?, for configuration: GatewayConfiguration) throws
    func removeSecret(for configuration: GatewayConfiguration) throws
}
