import Foundation
import Observation

@MainActor
@Observable
final class ConnectionModel {
    var configuration: GatewayConfiguration?
    var state: ConnectionState

    @ObservationIgnored private let configurationStore: GatewayConfigurationStore
    @ObservationIgnored private let credentialsStore: any CredentialsStore
    @ObservationIgnored private let clientFactory: OpenClawClientFactory
    @ObservationIgnored private(set) var activeClient: (any OpenClawClient)?

    init(
        configurationStore: GatewayConfigurationStore,
        credentialsStore: any CredentialsStore,
        clientFactory: @escaping OpenClawClientFactory)
    {
        let initialConfiguration = configurationStore.load()

        self.configurationStore = configurationStore
        self.credentialsStore = credentialsStore
        self.clientFactory = clientFactory
        self.configuration = initialConfiguration
        self.state = initialConfiguration == nil ? .notConfigured : .disconnected
    }

    var bannerError: UserFacingError? {
        switch self.state {
        case let .failed(error):
            error
        case .connectionLost:
            .connectionLost()
        default:
            nil
        }
    }

    var canConnect: Bool {
        !self.state.isBusy && self.configuration != nil && self.state != .connected
    }

    var canDisconnect: Bool {
        !self.state.isBusy && self.state == .connected
    }

    func saveConfiguration(_ configuration: GatewayConfiguration, secret: String?) -> Bool {
        let previousConfiguration = self.configuration

        do {
            try self.configurationStore.save(configuration)
            try self.credentialsStore.saveSecret(secret, for: configuration)

            if let previousConfiguration, previousConfiguration != configuration {
                try self.credentialsStore.removeSecret(for: previousConfiguration)
            }

            self.configuration = configuration
            if self.state != .connected && self.state != .connecting && self.state != .disconnecting {
                self.state = .disconnected
            }

            return true
        } catch {
            self.state = .failed(.persistenceFailed(details: error.localizedDescription))
            return false
        }
    }

    func connect() async {
        guard !self.state.isBusy else {
            return
        }

        guard let configuration = self.configuration else {
            self.state = .notConfigured
            return
        }

        guard self.state != .connected else {
            return
        }

        self.state = .connecting

        do {
            let secret = try self.credentialsStore.loadSecret(for: configuration)
            let client = self.clientFactory(configuration, secret) { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.reportConnectionLoss(error)
                }
            }

            try await client.connect(using: configuration)
            self.activeClient = client
            self.state = .connected
        } catch {
            self.activeClient = nil
            self.state = .failed(.wrapped(
                error,
                fallbackTitle: "Unable to connect",
                recoverySuggestion: "Check the gateway and try again."))
        }
    }

    func reconnect() async {
        await self.connect()
    }

    func disconnect() async {
        guard !self.state.isBusy else {
            return
        }

        guard self.activeClient != nil else {
            self.state = self.configuration == nil ? .notConfigured : .disconnected
            return
        }

        self.state = .disconnecting
        await self.activeClient?.disconnect()
        self.activeClient = nil
        self.state = self.configuration == nil ? .notConfigured : .disconnected
    }

    func reportConnectionLoss(_ error: UserFacingError = .connectionLost()) {
        guard self.configuration != nil else {
            self.state = .notConfigured
            return
        }

        self.activeClient = nil
        self.state = error.title == "Connection lost" ? .connectionLost : .failed(error)
    }
}
