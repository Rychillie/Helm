import Foundation

@MainActor
final class MockOpenClawClient: OpenClawClient {
    private let secret: String?
    private let connectShouldFail: Bool
    private let sendShouldFail: Bool
    private let connectionLossAfterReply: Bool
    private let onTransportLoss: @Sendable (UserFacingError) -> Void

    private var isConnected = false
    private var runtimeContext: ChatRuntimeContext?

    init(
        secret: String?,
        connectShouldFail: Bool = false,
        sendShouldFail: Bool = false,
        connectionLossAfterReply: Bool = false,
        onTransportLoss: @escaping @Sendable (UserFacingError) -> Void)
    {
        self.secret = secret
        self.connectShouldFail = connectShouldFail
        self.sendShouldFail = sendShouldFail
        self.connectionLossAfterReply = connectionLossAfterReply
        self.onTransportLoss = onTransportLoss
    }

    func connect(using configuration: GatewayConfiguration) async throws {
        try await Task.sleep(nanoseconds: 250_000_000)

        guard !self.connectShouldFail else {
            throw UserFacingError.connectionFailed(details: "The mock gateway rejected the connection.")
        }

        _ = self.secret
        self.isConnected = true
    }

    func disconnect() async {
        self.isConnected = false
        self.runtimeContext = nil
    }

    func prepareChatContext() async throws -> ChatRuntimeContext {
        guard self.isConnected else {
            throw UserFacingError.connectionRequired()
        }

        if let runtimeContext = self.runtimeContext {
            return runtimeContext
        }

        let runtimeContext = ChatRuntimeContext.ephemeral(prefix: "helm-mock")
        self.runtimeContext = runtimeContext
        return runtimeContext
    }

    func sendMessage(
        _ text: String,
        context: ChatRuntimeContext
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let replyChunks = Self.replyChunks(for: text, sessionKey: context.sessionKey)
        let shouldFail = self.sendShouldFail
        let shouldLoseConnection = self.connectionLossAfterReply
        let isConnected = self.isConnected

        return AsyncThrowingStream { continuation in
            guard isConnected else {
                continuation.finish(throwing: UserFacingError.connectionRequired())
                return
            }

            Task {
                continuation.yield(.started)

                if shouldFail {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continuation.yield(.failed(.sendFailed(details: "The mock gateway refused this message.")))
                    continuation.finish()
                    return
                }

                for chunk in replyChunks {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    continuation.yield(.delta(chunk))
                }

                continuation.yield(.completed)
                continuation.finish()

                guard shouldLoseConnection else {
                    return
                }

                self.forceConnectionLoss()
            }
        }
    }

    private func forceConnectionLoss() {
        guard self.isConnected else {
            return
        }

        self.isConnected = false
        self.onTransportLoss(.connectionLost(details: "The mock gateway dropped the connection."))
    }

    private static func replyChunks(for text: String, sessionKey: String) -> [String] {
        let response = [
            "Helm is connected to the mock gateway.",
            "It received your message:",
            "\"\(text)\".",
            "This reply is streaming through the same internal boundary the live adapter uses.",
            "Session: \(sessionKey).",
        ].joined(separator: " ")

        return response
            .split(separator: " ")
            .map { "\($0) " }
    }
}
