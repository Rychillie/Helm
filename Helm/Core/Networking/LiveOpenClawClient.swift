import Foundation
import OSLog

@MainActor
final class LiveOpenClawClient: OpenClawClient {
    private enum ProtocolConstants {
        static let version = 3
        static let clientID = "gateway-client"
        static let clientDisplayName = "Helm"
        static let clientPlatform = "ios"
        static let clientMode = "backend"
        static let clientRole = "operator"
        static let clientScopes = ["operator.read", "operator.write"]
        static let defaultMainSessionKey = "agent:main:main"
    }

    private enum StreamSource {
        case chat
        case agent
    }

    private struct GatewayRequestFrame<Params: Encodable>: Encodable {
        let type = "req"
        let id: String
        let method: String
        let params: Params
    }

    private struct GatewayRequestFrameWithoutParams: Encodable {
        let type = "req"
        let id: String
        let method: String
    }

    private struct ConnectParams: Encodable {
        struct Client: Encodable {
            let id: String
            let displayName: String
            let version: String
            let platform: String
            let mode: String
        }

        let minProtocol = ProtocolConstants.version
        let maxProtocol = ProtocolConstants.version
        let client: Client
        let role = ProtocolConstants.clientRole
        let scopes = ProtocolConstants.clientScopes
        let auth: [String: String]
    }

    private struct ChatSendParams: Encodable {
        let sessionKey: String
        let message: String
        let timeoutMs: Int
        let idempotencyKey: String
    }

    private struct ChatCompletionRequest: Encodable {
        struct Message: Encodable, Sendable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private let session: URLSession
    private let secret: String?
    private let onTransportLoss: @Sendable (UserFacingError) -> Void
    private let encoder = JSONEncoder()

    private var task: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var pendingRequests: [String: CheckedContinuation<Data, Error>] = [:]
    private var configuration: GatewayConfiguration?
    private var runtimeContext: ChatRuntimeContext?
    private var isConnected = false
    private var disconnectRequested = false
    private var connectChallengeReceived = false
    private var connectChallengeWaiter: CheckedContinuation<Void, Error>?
    private var activeStreamContinuation: AsyncThrowingStream<AssistantStreamEvent, Error>.Continuation?
    private var activeStreamSessionKey: String?
    private var activeStreamText = ""
    private var activeStreamSource: StreamSource?
    private var activeStreamTimeoutTask: Task<Void, Never>?
    private var httpFallbackHistory: [String: [ChatCompletionRequest.Message]] = [:]
    private var pendingHTTPFallbackUserMessage: String?

    init(
        secret: String?,
        session: URLSession = .shared,
        onTransportLoss: @escaping @Sendable (UserFacingError) -> Void)
    {
        self.secret = secret
        self.session = session
        self.onTransportLoss = onTransportLoss
    }

    func connect(using configuration: GatewayConfiguration) async throws {
        guard !self.isConnected else {
            return
        }

        self.disconnectRequested = false
        self.connectChallengeReceived = false
        self.configuration = configuration
        self.runtimeContext = nil

        let task = self.session.webSocketTask(with: configuration.endpoint)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
        self.task = task
        self.startReceiveLoop()

        do {
            try await self.waitForConnectChallenge(timeout: min(configuration.timeoutSeconds, 10))
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            let params = ConnectParams(
                client: .init(
                    id: ProtocolConstants.clientID,
                    displayName: ProtocolConstants.clientDisplayName,
                    version: version,
                    platform: ProtocolConstants.clientPlatform,
                    mode: ProtocolConstants.clientMode),
                    auth: self.connectAuth(for: configuration))

            let responseData = try await self.request(method: "connect", params: params, timeout: configuration.timeoutSeconds)
            try self.validateConnectResponse(responseData)
            self.isConnected = true
            AppLogger.gateway.info("Connected to OpenClaw gateway at \(configuration.endpoint.absoluteString, privacy: .public)")
        } catch {
            let userFacingError = UserFacingError.wrapped(
                error,
                fallbackTitle: "Unable to connect",
                recoverySuggestion: "Check the gateway and try again.")
            await self.finishDisconnect(closeCode: .goingAway, reason: nil, clearRuntimeContext: false)
            throw userFacingError
        }
    }

    func disconnect() async {
        await self.finishDisconnect(closeCode: .goingAway, reason: nil, clearRuntimeContext: true)
    }

    func prepareChatContext() async throws -> ChatRuntimeContext {
        guard self.isConnected else {
            throw UserFacingError.connectionRequired()
        }

        if let runtimeContext = self.runtimeContext {
            return runtimeContext
        }

        let runtimeContext = ChatRuntimeContext.primary(sessionKey: ProtocolConstants.defaultMainSessionKey)
        self.runtimeContext = runtimeContext
        return runtimeContext
    }

    func sendMessage(
        _ text: String,
        context: ChatRuntimeContext
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let timeoutSeconds = max(self.configuration?.timeoutSeconds ?? 30, 10)
        let sessionKey = context.sessionKey

        return AsyncThrowingStream { continuation in
            Task {
                var beganStreaming = false
                do {
                    guard self.isConnected else {
                        throw UserFacingError.connectionRequired()
                    }

                    guard self.activeStreamContinuation == nil else {
                        throw UserFacingError(
                            title: "Message in progress",
                            message: "Wait for the current reply before sending another message.",
                            recoverySuggestion: "Try again when the assistant finishes responding.")
                    }

                    let params = ChatSendParams(
                        sessionKey: sessionKey,
                        message: text,
                        timeoutMs: Int(timeoutSeconds * 1000),
                        idempotencyKey: UUID().uuidString.lowercased())

                    continuation.yield(.started)
                    self.beginActiveStream(
                        sessionKey: sessionKey,
                        continuation: continuation,
                        timeoutSeconds: timeoutSeconds + 15)
                    beganStreaming = true
                    self.pendingHTTPFallbackUserMessage = text
                    try await self.sendChatRequest(method: "chat.send", params: params, timeout: timeoutSeconds)
                } catch is CancellationError {
                    if beganStreaming {
                        self.failActiveStream(.sendFailed(details: "The request was cancelled."))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    let userFacingError = UserFacingError.wrapped(
                        error,
                        fallbackTitle: "Message failed",
                        recoverySuggestion: "Retry when the connection is ready.")
                    if beganStreaming {
                        self.failActiveStream(userFacingError)
                    } else {
                        continuation.finish(throwing: userFacingError)
                    }
                }
            }
        }
    }

    private func sendChatRequest<Params: Encodable>(
        method: String,
        params: Params,
        timeout: Double) async throws
    {
        do {
            _ = try await self.request(method: method, params: params, timeout: timeout)
        } catch let error as UserFacingError where error.title == "Request timed out" {
            // OpenClaw may keep the RPC open while streaming arrives over events.
            return
        } catch let error as UserFacingError where self.shouldUseHTTPFallback(for: error) {
            AppLogger.gateway.info("Falling back to HTTP chat completions because the gateway denied operator.write scope")
            try await self.sendChatCompletionFallback(timeout: timeout)
        }
    }

    private func shouldUseHTTPFallback(for error: UserFacingError) -> Bool {
        let message = error.message.lowercased()
        return message.contains("missing scope: operator.write")
    }

    private func sendChatCompletionFallback(timeout: Double) async throws {
        guard let configuration = self.configuration else {
            throw UserFacingError.connectionRequired()
        }

        guard let sessionKey = self.activeStreamSessionKey else {
            throw UserFacingError.sendFailed(details: "No active session is ready for fallback.")
        }

        guard let pendingUserMessage = self.pendingHTTPFallbackUserMessage else {
            throw UserFacingError.sendFailed(details: "No pending message is available for HTTP fallback.")
        }

        guard let url = self.chatCompletionsURL(for: configuration.endpoint) else {
            throw UserFacingError.sendFailed(details: "The gateway URL could not be converted to an HTTP chat endpoint.")
        }

        var transcript = self.httpFallbackHistory[sessionKey] ?? []
        transcript.append(.init(role: "user", content: pendingUserMessage))
        let requestBody = ChatCompletionRequest(
            model: "openclaw:main",
            messages: transcript)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout + 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let secret, configuration.authMode != .none {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(requestBody)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw UserFacingError.wrapped(
                error,
                fallbackTitle: "HTTP fallback failed",
                recoverySuggestion: "Check the gateway URL and try again.")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserFacingError.sendFailed(details: "The gateway returned an invalid HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw Self.httpFallbackError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw UserFacingError.sendFailed(details: "OpenClaw returned an empty chat completion response.")
        }

        self.emitStreamDelta(content)
        transcript.append(.init(role: "assistant", content: content))
        self.httpFallbackHistory[sessionKey] = transcript
        self.completeActiveStream()
    }

    private func chatCompletionsURL(for endpoint: URL) -> URL? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "ws":
            components.scheme = "http"
        case "wss":
            components.scheme = "https"
        default:
            break
        }

        let existingPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if existingPath.hasSuffix("v1/chat/completions") {
            components.path = "/" + existingPath
        } else if existingPath.isEmpty {
            components.path = "/v1/chat/completions"
        } else {
            components.path = "/" + existingPath + "/v1/chat/completions"
        }

        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func httpFallbackError(statusCode: Int, data: Data) -> UserFacingError {
        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch statusCode {
        case 401, 403:
            return UserFacingError(
                title: "HTTP fallback unauthorized",
                message: body.isEmpty ? "The gateway rejected the HTTP chat request." : body,
                recoverySuggestion: "Verify the gateway token or password.")
        case 404:
            return UserFacingError(
                title: "HTTP chat endpoint unavailable",
                message: body.isEmpty
                    ? "The gateway does not expose /v1/chat/completions."
                    : body,
                recoverySuggestion: "Enable the OpenAI chat completions endpoint on the OpenClaw gateway.")
        default:
            return UserFacingError(
                title: "HTTP fallback failed",
                message: body.isEmpty
                    ? "The gateway returned HTTP \(statusCode)."
                    : body,
                recoverySuggestion: "Review the gateway configuration and try again.")
        }
    }

    private func connectAuth(for configuration: GatewayConfiguration) -> [String: String] {
        guard let secret else {
            return [:]
        }

        switch configuration.authMode {
        case .none:
            return [:]
        case .sharedToken:
            return ["token": secret]
        case .password:
            return ["password": secret]
        }
    }

    private func startReceiveLoop() {
        self.receiveLoopTask?.cancel()
        self.receiveLoopTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let task = self.task else {
                return
            }

            do {
                let message = try await task.receive()
                try await self.handle(message: message)
            } catch is CancellationError {
                return
            } catch {
                let error = UserFacingError.connectionLost(details: error.localizedDescription)
                await self.handleTransportFailure(error)
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async throws {
        let data: Data

        switch message {
        case let .data(frameData):
            data = frameData
        case let .string(text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let frame = object as? [String: Any], let type = frame["type"] as? String else {
            return
        }

        switch type {
        case "res":
            try self.handleResponse(frame)
        case "event":
            self.handleEvent(frame)
        default:
            break
        }
    }

    private func handleResponse(_ frame: [String: Any]) throws {
        guard let id = frame["id"] as? String, let continuation = self.pendingRequests.removeValue(forKey: id) else {
            return
        }

        if (frame["ok"] as? Bool) == true {
            let payload = frame["payload"] ?? NSNull()
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
            continuation.resume(returning: data)
            return
        }

        continuation.resume(throwing: Self.responseError(from: frame["error"]))
    }

    private func handleEvent(_ frame: [String: Any]) {
        let eventName = frame["event"] as? String ?? "unknown"
        let payload = frame["payload"] as? [String: Any] ?? [:]

        if eventName == "connect.challenge" {
            AppLogger.gateway.debug("Received connect.challenge from OpenClaw gateway")
            self.connectChallengeReceived = true
            self.connectChallengeWaiter?.resume()
            self.connectChallengeWaiter = nil
            return
        }

        if eventName == "shutdown" {
            AppLogger.gateway.error("Gateway announced shutdown")
            self.failActiveStream(.connectionLost(details: "The gateway shut down the connection."))
            return
        }

        if eventName == "chat" {
            self.handleChatEvent(payload)
            return
        }

        if eventName == "agent" {
            self.handleAgentEvent(payload)
        }
    }

    private func beginActiveStream(
        sessionKey: String,
        continuation: AsyncThrowingStream<AssistantStreamEvent, Error>.Continuation,
        timeoutSeconds: Double)
    {
        self.activeStreamTimeoutTask?.cancel()
        self.activeStreamContinuation = continuation
        self.activeStreamSessionKey = sessionKey
        self.activeStreamText = ""
        self.activeStreamSource = nil
        self.activeStreamTimeoutTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(timeoutSeconds, 1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.timeoutActiveStreamIfNeeded()
        }
    }

    private func timeoutActiveStreamIfNeeded() {
        guard self.activeStreamContinuation != nil else {
            return
        }

        self.failActiveStream(.sendFailed(details: "OpenClaw did not return a visible reply."))
    }

    private func completeActiveStream() {
        guard let continuation = self.activeStreamContinuation else {
            return
        }

        continuation.yield(.completed)
        continuation.finish()
        self.resetActiveStream()
    }

    private func failActiveStream(_ error: UserFacingError) {
        guard let continuation = self.activeStreamContinuation else {
            return
        }

        continuation.yield(.failed(error))
        continuation.finish()
        self.resetActiveStream()
    }

    private func resetActiveStream() {
        self.activeStreamTimeoutTask?.cancel()
        self.activeStreamTimeoutTask = nil
        self.activeStreamContinuation = nil
        self.activeStreamSessionKey = nil
        self.activeStreamText = ""
        self.activeStreamSource = nil
        self.pendingHTTPFallbackUserMessage = nil
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        guard self.matchesActiveStream(payload: payload) else {
            return
        }

        let state = payload["state"] as? String

        if state == "delta" {
            if self.activeStreamSource == .agent {
                return
            }

            self.activeStreamSource = .chat
            let chunk = (payload["delta"] as? String)
                ?? ((payload["message"] as? [String: Any])?["delta"] as? String)
                ?? (payload["errorMessage"] as? String)

            if let chunk, !chunk.isEmpty {
                self.emitStreamDelta(chunk)
            }
            return
        }

        if state == "final" {
            let message = payload["message"] as? [String: Any]
            let finalText = Self.extractText(from: message?["content"])

            if !finalText.isEmpty, finalText.count >= self.activeStreamText.count {
                let delta = String(finalText.dropFirst(self.activeStreamText.count))
                if !delta.isEmpty {
                    self.emitStreamDelta(delta)
                }
            }

            if self.activeStreamText.isEmpty && finalText.isEmpty {
                self.failActiveStream(.sendFailed(details: "OpenClaw did not return a visible reply."))
            } else {
                self.completeActiveStream()
            }
            return
        }

        if state == "error" {
            let details = (payload["errorMessage"] as? String)
                ?? (payload["message"] as? String)
                ?? "OpenClaw returned an error."
            self.failActiveStream(.sendFailed(details: details))
        }
    }

    private func handleAgentEvent(_ payload: [String: Any]) {
        guard self.activeStreamContinuation != nil else {
            return
        }

        let stream = payload["stream"] as? String

        if stream == "assistant" {
            if self.activeStreamSource == .chat {
                return
            }

            self.activeStreamSource = .agent
            let data = payload["data"] as? [String: Any]
            let delta = data?["delta"] as? String
            if let delta, !delta.isEmpty {
                self.emitStreamDelta(delta)
            }
            return
        }

        if stream == "lifecycle" {
            let data = payload["data"] as? [String: Any]
            let phase = data?["phase"] as? String
            if phase == "error" {
                let details = (data?["error"] as? String) ?? "OpenClaw returned an error."
                self.failActiveStream(.sendFailed(details: details))
            } else if phase == "end", self.activeStreamSource == .agent, !self.activeStreamText.isEmpty {
                self.completeActiveStream()
            }
        }
    }

    private func emitStreamDelta(_ delta: String) {
        guard let continuation = self.activeStreamContinuation, !delta.isEmpty else {
            return
        }

        self.activeStreamText += delta
        continuation.yield(.delta(delta))
    }

    private func matchesActiveStream(payload: [String: Any]) -> Bool {
        guard let activeStreamSessionKey = self.activeStreamSessionKey else {
            return false
        }

        guard let eventSessionKey = payload["sessionKey"] as? String else {
            return true
        }

        return eventSessionKey == activeStreamSessionKey
    }

    private func waitForConnectChallenge(timeout: Double) async throws {
        if self.connectChallengeReceived {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            self.connectChallengeWaiter = continuation

            Task { @MainActor [weak self] in
                let nanoseconds = UInt64(max(timeout, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                self?.timeoutConnectChallengeIfNeeded()
            }
        }
    }

    private func timeoutConnectChallengeIfNeeded() {
        guard let continuation = self.connectChallengeWaiter else {
            return
        }

        self.connectChallengeWaiter = nil
        continuation.resume(throwing: UserFacingError.connectionFailed(
            details: "The gateway did not send a connect challenge."))
    }

    private func request<Params: Encodable>(
        method: String,
        params: Params,
        timeout: Double) async throws -> Data
    {
        let frame = GatewayRequestFrame(id: UUID().uuidString, method: method, params: params)
        let data = try self.encoder.encode(frame)
        return try await self.enqueueRequest(
            id: frame.id,
            method: method,
            data: data,
            timeout: timeout)
    }

    private func request(method: String, timeout: Double) async throws -> Data {
        let frame = GatewayRequestFrameWithoutParams(id: UUID().uuidString, method: method)
        let data = try self.encoder.encode(frame)
        return try await self.enqueueRequest(
            id: frame.id,
            method: method,
            data: data,
            timeout: timeout)
    }

    private func enqueueRequest(
        id: String,
        method: String,
        data: Data,
        timeout: Double) async throws -> Data
    {
        guard let task = self.task else {
            throw UserFacingError.connectionRequired()
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            Task { [weak self] in
                let nanoseconds = UInt64(max(timeout, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                self?.timeoutPendingRequest(id: id, method: method)
            }

            Task { [weak self] in
                do {
                    try await task.send(.data(data))
                } catch {
                    self?.failPendingRequest(
                        id: id,
                        error: UserFacingError.wrapped(
                            error,
                            fallbackTitle: "Request failed",
                            recoverySuggestion: "Check the connection and try again."))
                }
            }
        }
    }

    private func sendOnly<Params: Encodable>(method: String, params: Params) async throws {
        guard let task = self.task else {
            throw UserFacingError.connectionRequired()
        }

        let frame = GatewayRequestFrame(id: UUID().uuidString, method: method, params: params)
        let data = try self.encoder.encode(frame)

        do {
            try await task.send(.data(data))
        } catch {
            throw UserFacingError.wrapped(
                error,
                fallbackTitle: "Request failed",
                recoverySuggestion: "Check the connection and try again.")
        }
    }

    private func timeoutPendingRequest(id: String, method: String) {
        guard let continuation = self.pendingRequests.removeValue(forKey: id) else {
            return
        }

        continuation.resume(throwing: UserFacingError(
            title: "Request timed out",
            message: "\(method) did not finish in time.",
            recoverySuggestion: "Try again or reconnect."))
    }

    private func failPendingRequest(id: String, error: Error) {
        guard let continuation = self.pendingRequests.removeValue(forKey: id) else {
            return
        }

        continuation.resume(throwing: error)
    }

    private func handleTransportFailure(_ error: UserFacingError) async {
        let shouldNotify = self.isConnected && !self.disconnectRequested
        await self.finishDisconnect(closeCode: .abnormalClosure, reason: nil, clearRuntimeContext: false)

        guard shouldNotify else {
            return
        }

        self.onTransportLoss(error)
    }

    private func finishDisconnect(
        closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?,
        clearRuntimeContext: Bool) async
    {
        self.disconnectRequested = true
        self.isConnected = false
        self.connectChallengeReceived = false

        if clearRuntimeContext {
            self.runtimeContext = nil
        }

        if self.activeStreamContinuation != nil {
            self.failActiveStream(.connectionLost())
        }

        if let connectChallengeWaiter = self.connectChallengeWaiter {
            self.connectChallengeWaiter = nil
            connectChallengeWaiter.resume(throwing: UserFacingError.connectionLost())
        }

        self.receiveLoopTask?.cancel()
        self.receiveLoopTask = nil

        self.task?.cancel(with: closeCode, reason: reason)
        self.task = nil

        let pendingRequests = self.pendingRequests
        self.pendingRequests.removeAll()
        for continuation in pendingRequests.values {
            continuation.resume(throwing: UserFacingError.connectionLost())
        }
    }

    nonisolated private static func extractText(from value: Any?) -> String {
        switch value {
        case let text as String:
            return text
        case let array as [Any]:
            return array
                .map(Self.extractTextFragment(from:))
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case let dictionary as [String: Any]:
            if let text = dictionary["text"] as? String {
                return text
            }
            return Self.extractText(from: dictionary["content"])
        default:
            return ""
        }
    }

    nonisolated private static func extractTextFragment(from value: Any) -> String {
        if let text = value as? String {
            return text
        }

        guard let dictionary = value as? [String: Any] else {
            return ""
        }

        if let text = dictionary["text"] as? String {
            return text
        }

        if let content = dictionary["content"] as? String {
            return content
        }

        return Self.extractText(from: dictionary["content"])
    }

    nonisolated private static func responseError(from payload: Any?) -> UserFacingError {
        guard let dictionary = payload as? [String: Any] else {
            return UserFacingError.connectionFailed(details: "The gateway returned an unknown error.")
        }

        if let message = dictionary["message"] as? String, !message.isEmpty {
            return UserFacingError.connectionFailed(details: message)
        }

        if let detail = dictionary["detail"] as? String, !detail.isEmpty {
            return UserFacingError.connectionFailed(details: detail)
        }

        return UserFacingError.connectionFailed(details: "The gateway rejected the request.")
    }

    private func validateConnectResponse(_ responseData: Data) throws {
        let object = try JSONSerialization.jsonObject(with: responseData, options: [.fragmentsAllowed])
        guard let payload = object as? [String: Any] else {
            return
        }

        guard let payloadType = payload["type"] as? String else {
            return
        }

        guard payloadType == "hello-ok" else {
            throw UserFacingError.connectionFailed(
                details: "Unexpected connect response: \(payloadType)")
        }
    }

}
