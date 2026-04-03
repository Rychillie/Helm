import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let connectionModel: ConnectionModel
    let chatModel: ChatModel

    var showingConnectionSettings = false

    init() {
        let configurationStore = GatewayConfigurationStore()
        let credentialsStore = KeychainCredentialsStore()
        let environment = ProcessInfo.processInfo.environment
        let useMockGateway = environment["HELM_USE_MOCK_CLIENT"] == "1"
        let failConnect = environment["HELM_MOCK_FAIL_CONNECT"] == "1"
        let failSend = environment["HELM_MOCK_FAIL_SEND"] == "1"
        let connectionLossAfterReply = environment["HELM_MOCK_CONNECTION_LOST"] == "1"

        let factory: OpenClawClientFactory = { configuration, secret, onTransportLoss in
            if useMockGateway {
                return MockOpenClawClient(
                    secret: secret,
                    connectShouldFail: failConnect,
                    sendShouldFail: failSend,
                    connectionLossAfterReply: connectionLossAfterReply,
                    onTransportLoss: onTransportLoss)
            }

            return LiveOpenClawClient(secret: secret, onTransportLoss: onTransportLoss)
        }

        self.connectionModel = ConnectionModel(
            configurationStore: configurationStore,
            credentialsStore: credentialsStore,
            clientFactory: factory)
        self.chatModel = ChatModel()
    }

    func saveConfigurationAndConnect(configuration: GatewayConfiguration, secret: String?) async -> Bool {
        guard self.connectionModel.saveConfiguration(configuration, secret: secret) else {
            return false
        }

        Task {
            await self.connect()
        }
        return true
    }

    func connect() async {
        await self.connectionModel.connect()
        if self.connectionModel.state == .connected {
            self.chatModel.clearComposerError()
        }
    }

    func reconnect() async {
        await self.connectionModel.reconnect()
        if self.connectionModel.state == .connected {
            self.chatModel.clearComposerError()
        }
    }

    func disconnect() async {
        await self.connectionModel.disconnect()
        self.chatModel.resetRuntimeState()
    }

    func sendDraft() async {
        await self.chatModel.send(
            using: self.connectionModel.activeClient,
            connectionState: self.connectionModel.state)
    }

    func retry(_ message: ChatMessage) async {
        await self.chatModel.retry(
            message,
            using: self.connectionModel.activeClient,
            connectionState: self.connectionModel.state)
    }
}
