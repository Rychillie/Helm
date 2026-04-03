import Foundation
import Testing

@testable import Helm

struct ConnectionModelTests {
    @MainActor
    @Test
    func connectTransitionsToConnected() async throws {
        let client = TestOpenClawClient()
        let model = self.makeModel(client: client)
        let configuration = try #require(URL(string: "ws://127.0.0.1:18789"))

        #expect(model.saveConfiguration(
            GatewayConfiguration(endpoint: configuration, displayName: nil, timeoutSeconds: 30, authMode: .none),
            secret: nil))

        await model.connect()

        #expect(model.state == .connected)
        #expect(await client.snapshot().connectCalls == 1)
    }

    @MainActor
    @Test
    func connectionFailureMovesToFailedState() async throws {
        let client = TestOpenClawClient(connectError: UserFacingError.connectionFailed(details: "No route to host"))
        let model = self.makeModel(client: client)
        let configuration = try #require(URL(string: "ws://127.0.0.1:18789"))

        #expect(model.saveConfiguration(
            GatewayConfiguration(endpoint: configuration, displayName: nil, timeoutSeconds: 30, authMode: .none),
            secret: nil))

        await model.connect()

        guard case let .failed(error) = model.state else {
            Issue.record("Expected a failed state after a connection error")
            return
        }

        #expect(error.title == "Unable to connect")
    }

    @MainActor
    @Test
    func repeatedConnectTapsDoNotStartDuplicateWork() async throws {
        let client = TestOpenClawClient(connectDelayNanoseconds: 350_000_000)
        let model = self.makeModel(client: client)
        let configuration = try #require(URL(string: "ws://127.0.0.1:18789"))

        #expect(model.saveConfiguration(
            GatewayConfiguration(endpoint: configuration, displayName: nil, timeoutSeconds: 30, authMode: .none),
            secret: nil))

        async let first: Void = model.connect()
        async let second: Void = model.connect()
        _ = await (first, second)

        #expect(await client.snapshot().connectCalls == 1)
    }

    @MainActor
    @Test
    func repeatedDisconnectTapsDoNotStartDuplicateWork() async throws {
        let client = TestOpenClawClient(disconnectDelayNanoseconds: 350_000_000)
        let model = self.makeModel(client: client)
        let configuration = try #require(URL(string: "ws://127.0.0.1:18789"))

        #expect(model.saveConfiguration(
            GatewayConfiguration(endpoint: configuration, displayName: nil, timeoutSeconds: 30, authMode: .none),
            secret: nil))

        await model.connect()

        async let first: Void = model.disconnect()
        async let second: Void = model.disconnect()
        _ = await (first, second)

        #expect(await client.snapshot().disconnectCalls == 1)
        #expect(model.state == .disconnected)
    }

    @MainActor
    private func makeModel(client: TestOpenClawClient) -> ConnectionModel {
        let suiteName = "ConnectionModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = GatewayConfigurationStore(userDefaults: defaults, key: "gateway")
        let credentialsStore = InMemoryCredentialsStore()

        return ConnectionModel(
            configurationStore: store,
            credentialsStore: credentialsStore,
            clientFactory: { _, _, _ in client })
    }
}

private final class InMemoryCredentialsStore: CredentialsStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func loadSecret(for configuration: GatewayConfiguration) throws -> String? {
        self.lock.withLock {
            self.storage[self.key(for: configuration)]
        }
    }

    func saveSecret(_ secret: String?, for configuration: GatewayConfiguration) throws {
        self.lock.withLock {
            self.storage[self.key(for: configuration)] = secret
        }
    }

    func removeSecret(for configuration: GatewayConfiguration) throws {
        self.lock.withLock {
            self.storage.removeValue(forKey: self.key(for: configuration))
        }
    }

    private func key(for configuration: GatewayConfiguration) -> String {
        "\(configuration.endpoint.absoluteString)|\(configuration.authMode.rawValue)"
    }
}

private actor TestOpenClawClient: OpenClawClient {
    struct Snapshot: Sendable {
        let connectCalls: Int
        let disconnectCalls: Int
    }

    private let connectError: Error?
    private let connectDelayNanoseconds: UInt64
    private let disconnectDelayNanoseconds: UInt64

    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0

    init(
        connectError: Error? = nil,
        connectDelayNanoseconds: UInt64 = 0,
        disconnectDelayNanoseconds: UInt64 = 0)
    {
        self.connectError = connectError
        self.connectDelayNanoseconds = connectDelayNanoseconds
        self.disconnectDelayNanoseconds = disconnectDelayNanoseconds
    }

    func connect(using configuration: GatewayConfiguration) async throws {
        self.connectCalls += 1
        if self.connectDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: self.connectDelayNanoseconds)
        }

        if let connectError {
            throw connectError
        }
    }

    func disconnect() async {
        self.disconnectCalls += 1
        if self.disconnectDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: self.disconnectDelayNanoseconds)
        }
    }

    func prepareChatContext() async throws -> ChatRuntimeContext {
        .ephemeral(prefix: "test")
    }

    func sendMessage(
        _ text: String,
        context: ChatRuntimeContext
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(connectCalls: self.connectCalls, disconnectCalls: self.disconnectCalls)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        self.lock()
        defer { self.unlock() }
        return operation()
    }
}
